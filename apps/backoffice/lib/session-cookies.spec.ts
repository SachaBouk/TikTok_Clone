import { describe, expect, it } from 'vitest';
import { ACCESS_COOKIE, REFRESH_COOKIE, safeReturnPath, sessionCookies } from './session-cookies';

describe('sessionCookies', () => {
  it("fait expirer le cookie de l'access token une minute avant le jeton", () => {
    const [access, refresh] = sessionCookies({ accessToken: 'a', accessTokenExpiresIn: 900, refreshToken: 'r' });
    expect(access).toMatchObject({ name: ACCESS_COOKIE, value: 'a', options: { httpOnly: true, maxAge: 840 } });
    expect(refresh).toMatchObject({ name: REFRESH_COOKIE, value: 'r', options: { httpOnly: true, sameSite: 'lax' } });
  });
});

describe('safeReturnPath', () => {
  it('ne garde que les chemins internes', () => {
    expect(safeReturnPath('/videos?status=failed')).toBe('/videos?status=failed');
    expect(safeReturnPath('https://exemple.fr')).toBe('/');
    expect(safeReturnPath('//exemple.fr')).toBe('/');
    expect(safeReturnPath('/\\exemple.fr')).toBe('/');
    expect(safeReturnPath(null)).toBe('/');
  });
});
