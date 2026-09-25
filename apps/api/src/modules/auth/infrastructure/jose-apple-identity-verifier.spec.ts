import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT, type CryptoKey } from 'jose';
import { beforeAll, describe, expect, it } from 'vitest';
import { InvalidAppleTokenError } from '../domain/auth.errors';
import { JoseAppleIdentityVerifier } from './jose-apple-identity-verifier';

// Les clés d'Apple sont remplacées par une paire générée localement : on teste la vraie vérification
// (signature, émetteur, audience, expiration) sans appel réseau.
const BUNDLE_ID = 'com.example.tiktokclone';

describe('JoseAppleIdentityVerifier', () => {
  let appleKey: CryptoKey;
  let otherKey: CryptoKey;
  let verifier: JoseAppleIdentityVerifier;

  beforeAll(async () => {
    const apple = await generateKeyPair('RS256');
    appleKey = apple.privateKey;
    otherKey = (await generateKeyPair('RS256')).privateKey;
    const jwk = { ...(await exportJWK(apple.publicKey)), kid: 'apple-key', alg: 'RS256' };
    verifier = new JoseAppleIdentityVerifier(BUNDLE_ID, createLocalJWKSet({ keys: [jwk] }));
  });

  const token = (
    claims: Record<string, unknown> = {},
    { key = appleKey, issuer = 'https://appleid.apple.com', audience = BUNDLE_ID, expiresIn = '10m' } = {},
  ) =>
    new SignJWT({ email: 'relay@privaterelay.appleid.com', ...claims })
      .setProtectedHeader({ alg: 'RS256', kid: 'apple-key' })
      .setSubject('apple-sub-123')
      .setIssuer(issuer)
      .setAudience(audience)
      .setIssuedAt()
      .setExpirationTime(expiresIn)
      .sign(key);

  it('accepte un jeton valide et renvoie sub et email', async () => {
    await expect(verifier.verify(await token())).resolves.toEqual({
      sub: 'apple-sub-123',
      email: 'relay@privaterelay.appleid.com',
    });
  });

  it("renvoie un email nul si Apple ne l'a pas transmis", async () => {
    await expect(verifier.verify(await token({ email: undefined }))).resolves.toEqual({ sub: 'apple-sub-123', email: null });
  });

  it('refuse un jeton signé par une autre clé', async () => {
    await expect(verifier.verify(await token({}, { key: otherKey }))).rejects.toBeInstanceOf(InvalidAppleTokenError);
  });

  it.each([
    ['destiné à une autre app', { audience: 'com.autre.app' }],
    ['émis par un autre émetteur', { issuer: 'https://attaquant.example' }],
    ['expiré', { expiresIn: '-1m' }],
  ])('refuse un jeton %s', async (_label, options) => {
    await expect(verifier.verify(await token({}, options))).rejects.toBeInstanceOf(InvalidAppleTokenError);
  });

  it("refuse ce qui n'est pas un JWT", async () => {
    await expect(verifier.verify('pas-un-jwt')).rejects.toBeInstanceOf(InvalidAppleTokenError);
  });
});
