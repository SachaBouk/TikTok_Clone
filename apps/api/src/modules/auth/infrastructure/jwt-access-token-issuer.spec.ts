import { JwtService } from '@nestjs/jwt';
import { describe, expect, it } from 'vitest';
import { JwtAccessTokenIssuer } from './jwt-access-token-issuer';

const SECRET = 'x'.repeat(32);
const jwt = new JwtService({ secret: SECRET, signOptions: { expiresIn: 900, algorithm: 'HS256' } });
const issuer = new JwtAccessTokenIssuer(jwt);

describe('JwtAccessTokenIssuer', () => {
  it('vérifie un token émis : compte et expiration', async () => {
    const before = Date.now();
    const verified = await issuer.verify(await issuer.issue('alice'));
    expect(verified?.userId).toBe('alice');
    const ttl = verified!.expiresAt.getTime() - before;
    expect(ttl).toBeGreaterThan(898_000);
    expect(ttl).toBeLessThanOrEqual(901_000);
  });

  it('refuse un token expiré, falsifié, signé avec une autre clé ou non signé', async () => {
    const expired = await jwt.signAsync({ sub: 'alice' }, { expiresIn: -10 });
    const token = await issuer.issue('alice');
    const [header, , signature] = token.split('.');
    const tampered = `${header}.${Buffer.from(JSON.stringify({ sub: 'bob', exp: 9_999_999_999 })).toString('base64url')}.${signature}`;
    const otherKey = await new JwtService({ secret: 'y'.repeat(32) }).signAsync({ sub: 'alice' }, { expiresIn: 900 });
    const unsigned = `${Buffer.from('{"alg":"none","typ":"JWT"}').toString('base64url')}.${Buffer.from('{"sub":"alice","exp":9999999999}').toString('base64url')}.`;

    for (const invalid of [expired, tampered, otherKey, unsigned, 'pas-un-jwt', '']) {
      await expect(issuer.verify(invalid)).resolves.toBeNull();
    }
  });
});
