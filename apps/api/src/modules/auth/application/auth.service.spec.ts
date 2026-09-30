import { beforeEach, describe, expect, it } from 'vitest';
import { AccessTokenIssuer } from '../domain/access-token-issuer';
import { AppleIdentityVerifier, type AppleIdentity } from '../domain/apple-identity-verifier';
import {
  EmailAlreadyUsedError,
  InvalidAppleTokenError,
  InvalidCredentialsError,
  InvalidRefreshTokenError,
  TooManyLoginAttemptsError,
  UsernameAlreadyUsedError,
} from '../domain/auth.errors';
import { InMemoryRateLimiter } from '../../../rate-limit/in-memory-rate-limiter';
import { PasswordHasher } from '../domain/password-hasher';
import { InMemoryAuthAccountRepository } from '../infrastructure/in-memory-auth-account.repository';
import { InMemoryRefreshTokenRepository } from '../infrastructure/in-memory-refresh-token.repository';
import { AuthService } from './auth.service';

// Faux adaptateurs : rapides et déterministes (le vrai scrypt est testé à part).
class FakePasswordHasher extends PasswordHasher {
  async hash(password: string) {
    return `hashed:${password}`;
  }
  async verify(password: string, hash: string | null) {
    return hash === `hashed:${password}`;
  }
}

class FakeAccessTokenIssuer extends AccessTokenIssuer {
  async issue(userId: string) {
    return `access:${userId}`;
  }

  async verify(token: string) {
    return token.startsWith('access:') ? { userId: token.slice('access:'.length), expiresAt: new Date(0) } : null;
  }
}

class FakeAppleVerifier extends AppleIdentityVerifier {
  readonly identities = new Map<string, AppleIdentity>();
  async verify(identityToken: string) {
    const identity = this.identities.get(identityToken);
    if (!identity) throw new InvalidAppleTokenError();
    return identity;
  }
}

const registration = { email: 'Alice@Example.com ', password: 'motdepasse', username: 'alice', displayName: 'Alice' };

describe('AuthService', () => {
  let accounts: InMemoryAuthAccountRepository;
  let refreshTokens: InMemoryRefreshTokenRepository;
  let apple: FakeAppleVerifier;
  let now: Date;
  let limiter: InMemoryRateLimiter;
  let service: AuthService;

  beforeEach(() => {
    accounts = new InMemoryAuthAccountRepository();
    refreshTokens = new InMemoryRefreshTokenRepository();
    apple = new FakeAppleVerifier();
    now = new Date('2026-01-01T00:00:00Z');
    limiter = new InMemoryRateLimiter(() => now.getTime());
    service = new AuthService(
      accounts,
      refreshTokens,
      new FakePasswordHasher(),
      new FakeAccessTokenIssuer(),
      apple,
      { accessTokenTtlSeconds: 900, refreshTokenTtlDays: 30 },
      limiter,
      () => now,
    );
  });

  describe('limite des échecs de connexion (ADR-030)', () => {
    const fail = (email = 'alice@example.com', ip: string | null = '10.0.0.1') => service.login(email, 'mauvais', ip);

    it('5 échecs par email en 15 min, puis 429 même avec le bon mot de passe, jusqu’à la fin de la fenêtre', async () => {
      await service.register(registration);
      for (let i = 0; i < 5; i++) await expect(fail('alice@example.com', `10.0.0.${i}`)).rejects.toBeInstanceOf(InvalidCredentialsError);
      const blocked = await service.login('ALICE@example.com', 'motdepasse', '10.0.9.9').catch((e: unknown) => e);
      expect(blocked).toBeInstanceOf(TooManyLoginAttemptsError);
      expect((blocked as TooManyLoginAttemptsError).retryAfterSeconds).toBe(15 * 60);
      expect((blocked as TooManyLoginAttemptsError).message).toBe('Trop de tentatives de connexion : réessayez dans 15 min');

      now = new Date(now.getTime() + 15 * 60 * 1000);
      await expect(service.login('alice@example.com', 'motdepasse', '10.0.9.9')).resolves.toHaveProperty('accessToken');
    });

    it('une connexion réussie remet à zéro le compteur de l’email', async () => {
      await service.register(registration);
      for (let i = 0; i < 4; i++) await expect(fail()).rejects.toBeInstanceOf(InvalidCredentialsError);
      await service.login('alice@example.com', 'motdepasse', '10.0.0.2');
      for (let i = 0; i < 4; i++) await expect(fail('alice@example.com', '10.0.0.3')).rejects.toBeInstanceOf(InvalidCredentialsError);
      await expect(service.login('alice@example.com', 'motdepasse', '10.0.0.2')).resolves.toHaveProperty('accessToken');
    });

    it('20 échecs par IP en 15 min, sur des emails différents (inconnus compris)', async () => {
      await service.register(registration);
      for (let i = 0; i < 20; i++) await expect(fail(`inconnu${i}@example.com`)).rejects.toBeInstanceOf(InvalidCredentialsError);
      await expect(service.login('alice@example.com', 'motdepasse', '10.0.0.1')).rejects.toBeInstanceOf(TooManyLoginAttemptsError);
      await expect(service.login('alice@example.com', 'motdepasse', '10.0.0.2')).resolves.toHaveProperty('accessToken');
    });

    it('les connexions réussies ne comptent pas ; sans IP, seule la limite par email s’applique', async () => {
      await service.register(registration);
      for (let i = 0; i < 30; i++) await service.login('alice@example.com', 'motdepasse', '10.0.0.1');
      for (let i = 0; i < 5; i++) await expect(fail('alice@example.com', null)).rejects.toBeInstanceOf(InvalidCredentialsError);
      await expect(fail('alice@example.com', null)).rejects.toBeInstanceOf(TooManyLoginAttemptsError);
    });
  });

  describe('inscription et connexion par email', () => {
    it("crée le compte, normalise l'email et ouvre une session", async () => {
      const tokens = await service.register(registration);

      expect(accounts.accounts[0]).toMatchObject({ email: 'alice@example.com', passwordHash: 'hashed:motdepasse' });
      expect(tokens.accessToken).toBe(`access:${accounts.accounts[0]!.id}`);
      expect(tokens.accessTokenExpiresIn).toBe(900);
      expect(tokens.refreshToken).toMatch(/^[A-Za-z0-9_-]{43}$/);
    });

    it('ne stocke jamais le refresh token en clair', async () => {
      const { refreshToken } = await service.register(registration);
      expect(refreshTokens.tokens[0]!.tokenHash).not.toBe(refreshToken);
      expect(refreshTokens.tokens[0]!.tokenHash).toMatch(/^[0-9a-f]{64}$/);
    });

    it('refuse un email ou un pseudo déjà pris, et le pseudo réservé « me »', async () => {
      await service.register(registration);
      await expect(service.register({ ...registration, username: 'autre' })).rejects.toBeInstanceOf(EmailAlreadyUsedError);
      await expect(service.register({ ...registration, email: 'b@b.fr' })).rejects.toBeInstanceOf(UsernameAlreadyUsedError);
      await expect(service.register({ ...registration, email: 'c@c.fr', username: 'me' })).rejects.toBeInstanceOf(
        UsernameAlreadyUsedError,
      );
    });

    it('connecte avec le bon mot de passe, email insensible à la casse', async () => {
      await service.register(registration);
      await expect(service.login('ALICE@example.com', 'motdepasse')).resolves.toHaveProperty('accessToken');
    });

    it('refuse un mauvais mot de passe ou un email inconnu avec la même erreur', async () => {
      await service.register(registration);
      await expect(service.login('alice@example.com', 'mauvais')).rejects.toBeInstanceOf(InvalidCredentialsError);
      await expect(service.login('inconnu@example.com', 'motdepasse')).rejects.toBeInstanceOf(InvalidCredentialsError);
    });
  });

  describe('rotation des refresh tokens', () => {
    it('échange un refresh token contre une nouvelle paire, dans la même session', async () => {
      const first = await service.register(registration);
      const second = await service.refresh(first.refreshToken);

      expect(second.refreshToken).not.toBe(first.refreshToken);
      expect(refreshTokens.tokens).toHaveLength(2);
      expect(refreshTokens.tokens[0]!.familyId).toBe(refreshTokens.tokens[1]!.familyId);
      expect(refreshTokens.tokens[0]!.revokedAt).toEqual(now);
    });

    it('détecte la réutilisation : rejouer un ancien token révoque toute la session', async () => {
      const first = await service.register(registration);
      const second = await service.refresh(first.refreshToken);

      await expect(service.refresh(first.refreshToken)).rejects.toBeInstanceOf(InvalidRefreshTokenError);
      // Le token légitime le plus récent est révoqué lui aussi : le voleur comme la victime doivent se reconnecter.
      await expect(service.refresh(second.refreshToken)).rejects.toBeInstanceOf(InvalidRefreshTokenError);
    });

    it("n'affecte pas les autres sessions du même compte", async () => {
      const phone = await service.register(registration);
      const tablet = await service.login('alice@example.com', 'motdepasse');
      await service.refresh(phone.refreshToken);
      await expect(service.refresh(phone.refreshToken)).rejects.toBeInstanceOf(InvalidRefreshTokenError);

      await expect(service.refresh(tablet.refreshToken)).resolves.toHaveProperty('refreshToken');
    });

    it('refuse un token expiré', async () => {
      const { refreshToken } = await service.register(registration);
      now = new Date('2026-01-31T00:00:00Z'); // 30 jours plus tard
      await expect(service.refresh(refreshToken)).rejects.toBeInstanceOf(InvalidRefreshTokenError);
    });

    it('refuse un token inconnu', async () => {
      await expect(service.refresh('inconnu')).rejects.toBeInstanceOf(InvalidRefreshTokenError);
    });
  });

  describe('déconnexion', () => {
    it('révoque la session ; un token inconnu est ignoré', async () => {
      const { refreshToken } = await service.register(registration);
      await service.logout(refreshToken);
      await expect(service.refresh(refreshToken)).rejects.toBeInstanceOf(InvalidRefreshTokenError);
      await expect(service.logout('inconnu')).resolves.toBeUndefined();
    });
  });

  describe('Sign in with Apple', () => {
    it('crée un compte à la première connexion, puis reconnecte le même compte', async () => {
      apple.identities.set('jeton-1', { sub: 'apple-123', email: 'relay@privaterelay.appleid.com' });
      apple.identities.set('jeton-2', { sub: 'apple-123', email: null });

      await service.loginWithApple({ identityToken: 'jeton-1', displayName: ' Bob ' });
      await service.loginWithApple({ identityToken: 'jeton-2' });

      expect(accounts.accounts).toHaveLength(1);
      expect(accounts.accounts[0]).toMatchObject({
        appleSub: 'apple-123',
        email: 'relay@privaterelay.appleid.com',
        passwordHash: null,
        displayName: 'Bob',
      });
      expect(accounts.accounts[0]!.username).toMatch(/^user\d{10}$/);
    });

    it('utilise un nom par défaut si Apple ne fournit pas de nom', async () => {
      apple.identities.set('jeton', { sub: 'apple-456', email: null });
      await service.loginWithApple({ identityToken: 'jeton' });
      expect(accounts.accounts[0]).toMatchObject({ displayName: 'Utilisateur', email: null });
    });

    it("refuse un email Apple déjà utilisé par un compte email / mot de passe (pas de liaison automatique)", async () => {
      await service.register(registration);
      apple.identities.set('jeton', { sub: 'apple-789', email: 'alice@example.com' });
      await expect(service.loginWithApple({ identityToken: 'jeton' })).rejects.toBeInstanceOf(EmailAlreadyUsedError);
    });

    it('refuse un jeton Apple invalide', async () => {
      await expect(service.loginWithApple({ identityToken: 'faux' })).rejects.toBeInstanceOf(InvalidAppleTokenError);
    });

    it('un compte Apple ne peut pas se connecter par mot de passe', async () => {
      apple.identities.set('jeton', { sub: 'apple-1', email: 'x@y.fr' });
      await service.loginWithApple({ identityToken: 'jeton' });
      await expect(service.login('x@y.fr', 'nimportequoi')).rejects.toBeInstanceOf(InvalidCredentialsError);
    });
  });

  describe('rôle administrateur (ADR-004)', () => {
    it('ne reconnaît que les comptes au rôle admin', async () => {
      await service.register(registration);
      await service.register({ ...registration, email: 'bob@example.com', username: 'bob' });
      const [alice, bob] = accounts.accounts;
      accounts.adminIds.add(alice!.id);

      await expect(service.isAdmin(alice!.id)).resolves.toBe(true);
      await expect(service.isAdmin(bob!.id)).resolves.toBe(false);
      await expect(service.isAdmin('inconnu')).resolves.toBe(false);
      await expect(service.findAdminIds([alice!.id, bob!.id, alice!.id])).resolves.toEqual(new Set([alice!.id]));
    });

    it('prend en compte un rôle retiré aussitôt', async () => {
      await service.register(registration);
      const id = accounts.accounts[0]!.id;
      accounts.adminIds.add(id);
      await expect(service.isAdmin(id)).resolves.toBe(true);
      accounts.adminIds.delete(id);
      await expect(service.isAdmin(id)).resolves.toBe(false);
    });
  });
});
