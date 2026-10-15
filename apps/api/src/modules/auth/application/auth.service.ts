import { createHash, randomBytes, randomInt, randomUUID } from 'node:crypto';
import type { AccessTokenIssuer, VerifiedAccessToken } from '../domain/access-token-issuer';
import { type AccountSuspension, type AuthAccount, type AuthTokens, MAX_SUSPENSION_REASON_LENGTH } from '../domain/auth-account';
import type { AuthAccountRepository } from '../domain/auth-account.repository';
import type { AppleIdentityVerifier } from '../domain/apple-identity-verifier';
import {
  AccountSuspendedError,
  CannotSuspendAdminError,
  InvalidCredentialsError,
  InvalidRefreshTokenError,
  InvalidRegistrationError,
  InvalidSuspensionReasonError,
  TooManyLoginAttemptsError,
  TooManySignupsError,
  UsernameAlreadyUsedError,
} from '../domain/auth.errors';
import { LOGIN_ACCOUNT_RATE_LIMITS, LOGIN_IP_RATE_LIMITS, parseLoginIdentifier, SIGNUP_IP_RATE_LIMITS } from '../domain/login-rules';
import { ageOn, isValidPassword, MAX_PASSWORD_LENGTH, MIN_PASSWORD_LENGTH, MIN_SIGNUP_AGE, parseBirthDate } from '../domain/registration-rules';
import type { PasswordHasher } from '../domain/password-hasher';
import type { RefreshTokenRepository } from '../domain/refresh-token.repository';
import { RESERVED_USERNAMES } from '../../users/domain/profile-rules';
import type { RateLimiter } from '../../../rate-limit/rate-limiter';
import type { SuspendedAccounts } from '../../../suspension/suspended-accounts';

export interface AuthSettings {
  accessTokenTtlSeconds: number;
  refreshTokenTtlDays: number;
}

export interface RegisterInput {
  email: string;
  password: string;
  username: string;
  // Facultatif (ADR-055) : le pseudo par défaut, modifiable ensuite dans le profil.
  displayName?: string;
  // `AAAA-MM-JJ` ; 13 ans au moins.
  birthDate: string;
}

export interface AppleLoginInput {
  identityToken: string;
  // Apple ne transmet le nom qu'à la première connexion, et seulement à l'app (pas dans le token).
  displayName?: string;
}

const APPLE_USERNAME_ATTEMPTS = 5;
const DEFAULT_DISPLAY_NAME = 'Utilisateur';

// Service applicatif du module auth (ADR-003, ADR-010).
// Refresh tokens : opaques (256 bits aléatoires), seul leur SHA-256 est stocké, rotation à chaque usage.
// Un token déjà utilisé qui revient est traité comme un vol : toute la session (famille) est révoquée.
// Suspension (ADR-037) : connexion refusée (403), sessions révoquées, et chaque access token d'un compte suspendu
// est refusé, sur une route (JwtStrategy) comme au handshake WebSocket, d'après le registre partagé.
export class AuthService {
  constructor(
    private readonly accounts: AuthAccountRepository,
    private readonly refreshTokens: RefreshTokenRepository,
    private readonly passwords: PasswordHasher,
    private readonly accessTokens: AccessTokenIssuer,
    private readonly apple: AppleIdentityVerifier,
    private readonly settings: AuthSettings,
    private readonly rateLimiter: RateLimiter,
    private readonly suspended: SuspendedAccounts,
    private readonly now: () => Date = () => new Date(),
  ) {}

  // `ip` : adresse du client (null hors HTTP). Comptes créés limités par IP (ADR-039) : la limite est vérifiée
  // avant la création, et seule une création réussie est comptée.
  // Règles de l'ADR-055 vérifiées d'abord : date de naissance (13 ans au moins), mot de passe (lettre et chiffre).
  async register(input: RegisterInput, ip: string | null = null): Promise<AuthTokens> {
    const birthDate = parseBirthDate(input.birthDate, this.now());
    if (!birthDate) throw new InvalidRegistrationError('Date de naissance invalide');
    if (ageOn(birthDate, this.now()) < MIN_SIGNUP_AGE) {
      throw new InvalidRegistrationError(`Il faut avoir au moins ${MIN_SIGNUP_AGE} ans pour créer un compte`);
    }
    if (!isValidPassword(input.password)) {
      throw new InvalidRegistrationError(
        `Mot de passe : ${MIN_PASSWORD_LENGTH} à ${MAX_PASSWORD_LENGTH} caractères, avec au moins une lettre et un chiffre`,
      );
    }
    if (RESERVED_USERNAMES.has(input.username)) throw new UsernameAlreadyUsedError(input.username);
    const ipKey = ip ? `signup-ip:${ip}` : null;
    if (ipKey) {
      const retryAfter = await this.rateLimiter.check(ipKey, SIGNUP_IP_RATE_LIMITS);
      if (retryAfter !== null) throw new TooManySignupsError(retryAfter);
    }

    const account = await this.accounts.create({
      email: normalizeEmail(input.email),
      passwordHash: await this.passwords.hash(input.password),
      appleSub: null,
      username: input.username,
      displayName: input.displayName?.trim() || input.username,
      birthDate,
    });
    if (ipKey) await this.rateLimiter.hit(ipKey, SIGNUP_IP_RATE_LIMITS);
    return this.startSession(account.id);
  }

  // `ip` : adresse du client (null hors HTTP). Échecs limités par email et par IP (ADR-030) : la limite est
  // vérifiée avant le mot de passe (qui n'est alors pas testé), et un échec est compté après coup.
  // Connexion par email ou pseudo (ADR-055) et mot de passe.
  async login(identifier: string, password: string, ip: string | null = null): Promise<AuthTokens> {
    const parsed = parseLoginIdentifier(identifier);
    const account = parsed.kind === 'email' ? await this.accounts.findByEmail(parsed.value) : await this.accounts.findByUsername(parsed.value);
    // Compté par compte : email et pseudo du même compte partagent la limite. Identifiant inconnu : son empreinte
    // (aucun identifiant en clair dans les clés Redis).
    const accountKey = `login-account:${account?.id ?? createHash('sha256').update(`${parsed.kind}:${parsed.value}`).digest('hex')}`;
    const ipKey = ip ? `login-ip:${ip}` : null;
    const waits = await Promise.all([
      this.rateLimiter.check(accountKey, LOGIN_ACCOUNT_RATE_LIMITS),
      ipKey ? this.rateLimiter.check(ipKey, LOGIN_IP_RATE_LIMITS) : null,
    ]);
    const retryAfter = Math.max(...waits.map((wait) => wait ?? 0));
    if (retryAfter > 0) throw new TooManyLoginAttemptsError(retryAfter);

    // Vérification faite même si le compte n'existe pas (voir PasswordHasher.verify).
    const valid = await this.passwords.verify(password, account?.passwordHash ?? null);
    if (!account || !valid) {
      await Promise.all([this.rateLimiter.hit(accountKey, LOGIN_ACCOUNT_RATE_LIMITS), ipKey && this.rateLimiter.hit(ipKey, LOGIN_IP_RATE_LIMITS)]);
      throw new InvalidCredentialsError();
    }
    await this.rateLimiter.reset(accountKey, LOGIN_ACCOUNT_RATE_LIMITS);
    await this.assertNotSuspended(account.id);
    return this.startSession(account.id);
  }

  // Connexion ou inscription via Sign in with Apple. Pas de liaison automatique avec un compte
  // email / mot de passe existant : si l'email Apple est déjà pris, EmailAlreadyUsedError.
  async loginWithApple(input: AppleLoginInput): Promise<AuthTokens> {
    const identity = await this.apple.verify(input.identityToken);
    const account =
      (await this.accounts.findByAppleSub(identity.sub)) ?? (await this.createAppleAccount(identity.sub, identity.email, input.displayName));
    await this.assertNotSuspended(account.id);
    return this.startSession(account.id);
  }

  async refresh(refreshToken: string): Promise<AuthTokens> {
    const token = await this.refreshTokens.findByHash(hashToken(refreshToken));
    if (!token) throw new InvalidRefreshTokenError();

    const now = this.now();
    if (token.revokedAt) {
      await this.refreshTokens.revokeFamily(token.familyId, now);
      throw new InvalidRefreshTokenError();
    }
    if (token.expiresAt <= now) throw new InvalidRefreshTokenError();
    // Ses sessions sont révoquées à la suspension ; ceci couvre une rotation commencée au même moment.
    if (await this.suspended.has(token.userId)) throw new InvalidRefreshTokenError();

    // Deux rotations concurrentes du même token : seule la première gagne, la seconde est une réutilisation.
    if (!(await this.refreshTokens.revoke(token.id, now))) {
      await this.refreshTokens.revokeFamily(token.familyId, now);
      throw new InvalidRefreshTokenError();
    }
    return this.issueTokens(token.userId, token.familyId);
  }

  // Pour les connexions hors HTTP (WebSocket, ADR-011) : compte et expiration du token, ou null s'il est invalide.
  async verifyAccessToken(accessToken: string): Promise<VerifiedAccessToken | null> {
    const verified = await this.accessTokens.verify(accessToken);
    return verified && !(await this.suspended.has(verified.userId)) ? verified : null;
  }

  // Compte suspendu (registre Redis, sans lecture de la base) : ses access tokens sont refusés.
  isSuspended(userId: string): Promise<boolean> {
    return this.suspended.has(userId);
  }

  // Suspension par un administrateur (ADR-037) : enregistrée en base, ajoutée au registre partagé (contenus masqués,
  // requêtes refusées), puis toutes les sessions sont révoquées. La fermeture des WebSocket revient à l'appelant
  // (module admin), auth ne dépendant pas de realtime. Un compte déjà suspendu garde sa suspension (date, motif,
  // auteur). Un administrateur ne peut pas être suspendu, ni soi-même. Null si le compte n'existe pas.
  async suspend(userId: string, adminId: string, reason: string): Promise<AccountSuspension | null> {
    const text = reason.trim();
    if (!text || text.length > MAX_SUSPENSION_REASON_LENGTH) throw new InvalidSuspensionReasonError(MAX_SUSPENSION_REASON_LENGTH);
    if (userId === adminId || (await this.isAdmin(userId))) throw new CannotSuspendAdminError();
    const suspension = await this.accounts.suspend({ userId, suspendedAt: this.now(), reason: text, suspendedBy: adminId });
    if (!suspension) return null;
    await this.suspended.add(userId);
    await this.refreshTokens.revokeAllForUser(userId, this.now());
    return suspension;
  }

  // Levée : le compte peut se reconnecter, ses contenus réapparaissent. Idempotent.
  async liftSuspension(userId: string): Promise<void> {
    await this.accounts.liftSuspension(userId);
    await this.suspended.remove(userId);
  }

  // Suspensions en cours parmi `ids` (backoffice), lues en base.
  getSuspensions(ids: string[]): Promise<Map<string, AccountSuspension>> {
    return this.accounts.findSuspensions([...new Set(ids)]);
  }

  countSuspended(): Promise<number> {
    return this.accounts.countSuspended();
  }

  // Comptes suspendus, du plus récemment suspendu au plus ancien (backoffice), après le compte `afterUserId`.
  listSuspended(afterUserId: string | null, limit: number): Promise<string[]> {
    return this.accounts.listSuspended(afterUserId, limit);
  }

  // Au démarrage de l'API : le registre Redis est reconstruit depuis la base, qui fait foi.
  async syncSuspendedAccounts(): Promise<number> {
    const ids = await this.accounts.listSuspendedIds();
    await this.suspended.replaceAll(ids);
    return ids.length;
  }

  // Rôle administrateur (ADR-004), relu en base à chaque requête d'administration : un rôle retiré
  // prend effet aussitôt, sans attendre l'expiration de l'access token.
  async isAdmin(userId: string): Promise<boolean> {
    return (await this.accounts.findAdminIds([userId])).has(userId);
  }

  // Administrateurs parmi `ids` (liste des comptes du backoffice).
  findAdminIds(ids: string[]): Promise<Set<string>> {
    return this.accounts.findAdminIds([...new Set(ids)]);
  }

  // Déconnexion de l'appareil : révoque la session. Idempotent, ne révèle rien si le token est inconnu.
  async logout(refreshToken: string): Promise<void> {
    const token = await this.refreshTokens.findByHash(hashToken(refreshToken));
    if (token) await this.refreshTokens.revokeFamily(token.familyId, this.now());
  }

  private async createAppleAccount(appleSub: string, email: string | null, displayName?: string): Promise<AuthAccount> {
    // Pseudo généré (modifiable ensuite par l'utilisateur) ; nouvel essai en cas de collision.
    for (let attempt = 1; ; attempt++) {
      try {
        return await this.accounts.create({
          email: email ? normalizeEmail(email) : null,
          passwordHash: null,
          appleSub,
          username: `user${randomInt(1e9, 1e10)}`,
          displayName: displayName?.trim() || DEFAULT_DISPLAY_NAME,
          // Apple ne la donne pas : à demander après coup (ADR-055).
          birthDate: null,
        });
      } catch (error) {
        if (!(error instanceof UsernameAlreadyUsedError) || attempt >= APPLE_USERNAME_ATTEMPTS) throw error;
      }
    }
  }

  // Lu en base (source de vérité) : la connexion ne dépend pas du registre.
  private async assertNotSuspended(userId: string): Promise<void> {
    if ((await this.accounts.findSuspensions([userId])).has(userId)) throw new AccountSuspendedError();
  }

  private startSession(userId: string): Promise<AuthTokens> {
    return this.issueTokens(userId, randomUUID());
  }

  private async issueTokens(userId: string, familyId: string): Promise<AuthTokens> {
    const refreshToken = randomBytes(32).toString('base64url');
    const expiresAt = new Date(this.now().getTime() + this.settings.refreshTokenTtlDays * 24 * 60 * 60 * 1000);
    await this.refreshTokens.create({ userId, familyId, tokenHash: hashToken(refreshToken), expiresAt });

    return {
      accessToken: await this.accessTokens.issue(userId),
      accessTokenExpiresIn: this.settings.accessTokenTtlSeconds,
      refreshToken,
    };
  }
}

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

// SHA-256 suffit ici : le token a 256 bits d'entropie, un hachage lent (scrypt) n'apporterait rien.
function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}
