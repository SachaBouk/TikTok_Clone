import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from 'jose';
import type { AppleIdentity } from '../domain/apple-identity-verifier';
import { AppleIdentityVerifier } from '../domain/apple-identity-verifier';
import { InvalidAppleTokenError } from '../domain/auth.errors';

const APPLE_ISSUER = 'https://appleid.apple.com';
// Clés publiques d'Apple ; `jose` les met en cache et les recharge quand Apple en change.
const APPLE_KEYS_URL = new URL('https://appleid.apple.com/auth/keys');

// Vérifie la signature (clés publiques Apple), l'émetteur, l'audience (bundle ID de l'app) et l'expiration.
export class JoseAppleIdentityVerifier extends AppleIdentityVerifier {
  constructor(
    private readonly bundleId: string,
    // Injectable pour les tests (clés générées localement).
    private readonly keys: JWTVerifyGetKey = createRemoteJWKSet(APPLE_KEYS_URL),
  ) {
    super();
  }

  async verify(identityToken: string): Promise<AppleIdentity> {
    try {
      const { payload } = await jwtVerify(identityToken, this.keys, {
        issuer: APPLE_ISSUER,
        audience: this.bundleId,
        algorithms: ['RS256'],
      });
      if (!payload.sub) throw new InvalidAppleTokenError();
      return { sub: payload.sub, email: typeof payload.email === 'string' ? payload.email : null };
    } catch {
      throw new InvalidAppleTokenError();
    }
  }
}
