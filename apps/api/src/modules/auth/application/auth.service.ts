import { createHash, randomBytes, randomInt, randomUUID } from 'node:crypto';
import type { AccessTokenIssuer, VerifiedAccessToken } from '../domain/access-token-issuer';
import type { AuthAccount, AuthTokens } from '../domain/auth-account';
import type { AuthAccountRepository } from '../domain/auth-account.repository';
import type { AppleIdentityVerifier } from '../domain/apple-identity-verifier';
import { InvalidCredentialsError, InvalidRefreshTokenError, UsernameAlreadyUsedError } from '../domain/auth.errors';
import type { PasswordHasher } from '../domain/password-hasher';
import type { RefreshTokenRepository } from '../domain/refresh-token.repository';
import { RESERVED_USERNAMES } from '../../users/domain/profile-rules';

export interface AuthSettings {
  accessTokenTtlSeconds: number;
  refreshTokenTtlDays: number;
}

export interface RegisterInput {
  email: string;
  password: string;
  username: string;
  displayName: string;
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
export class AuthService {
  constructor(
    private readonly accounts: AuthAccountRepository,
    private readonly refreshTokens: RefreshTokenRepository,
    private readonly passwords: PasswordHasher,
    private readonly accessTokens: AccessTokenIssuer,
    private readonly apple: AppleIdentityVerifier,
    private readonly settings: AuthSettings,
    private readonly now: () => Date = () => new Date(),
  ) {}

  async register(input: RegisterInput): Promise<AuthTokens> {
    if (RESERVED_USERNAMES.has(input.username)) throw new UsernameAlreadyUsedError(input.username);

    const account = await this.accounts.create({
      email: normalizeEmail(input.email),
      passwordHash: await this.passwords.hash(input.password),
      appleSub: null,
      username: input.username,
      displayName: input.displayName.trim(),
    });
    return this.startSession(account.id);
  }

  async login(email: string, password: string): Promise<AuthTokens> {
    const account = await this.accounts.findByEmail(normalizeEmail(email));
    // Vérification faite même si le compte n'existe pas (voir PasswordHasher.verify).
    const valid = await this.passwords.verify(password, account?.passwordHash ?? null);
    if (!account || !valid) throw new InvalidCredentialsError();
    return this.startSession(account.id);
  }

  // Connexion ou inscription via Sign in with Apple. Pas de liaison automatique avec un compte
  // email / mot de passe existant : si l'email Apple est déjà pris, EmailAlreadyUsedError.
  async loginWithApple(input: AppleLoginInput): Promise<AuthTokens> {
    const identity = await this.apple.verify(input.identityToken);
    const account =
      (await this.accounts.findByAppleSub(identity.sub)) ??
      (await this.createAppleAccount(identity.sub, identity.email, input.displayName));
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

    // Deux rotations concurrentes du même token : seule la première gagne, la seconde est une réutilisation.
    if (!(await this.refreshTokens.revoke(token.id, now))) {
      await this.refreshTokens.revokeFamily(token.familyId, now);
      throw new InvalidRefreshTokenError();
    }
    return this.issueTokens(token.userId, token.familyId);
  }

  // Pour les connexions hors HTTP (WebSocket, ADR-011) : compte et expiration du token, ou null s'il est invalide.
  verifyAccessToken(accessToken: string): Promise<VerifiedAccessToken | null> {
    return this.accessTokens.verify(accessToken);
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
        });
      } catch (error) {
        if (!(error instanceof UsernameAlreadyUsedError) || attempt >= APPLE_USERNAME_ATTEMPTS) throw error;
      }
    }
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
