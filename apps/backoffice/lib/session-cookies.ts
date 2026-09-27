import type { AuthTokensDto } from '@repo/shared';

// Session du backoffice : les jetons de l'API (ADR-010) sont gardés dans des cookies httpOnly, lus
// uniquement côté serveur. Le navigateur ne voit jamais un jeton.
export const ACCESS_COOKIE = 'bo_access';
export const REFRESH_COOKIE = 'bo_refresh';

// Le cookie de l'access token disparaît un peu avant le jeton : le proxy rafraîchit la session avant
// qu'une page ou une Server Action n'envoie un jeton expiré.
const ACCESS_MARGIN_SECONDS = 60;
// Durée d'une session sans activité (le refresh token de l'API vit plus longtemps).
export const SESSION_MAX_AGE_SECONDS = 7 * 24 * 60 * 60;

export interface SessionCookie {
  name: string;
  value: string;
  options: { httpOnly: true; secure: boolean; sameSite: 'lax'; path: '/'; maxAge: number };
}

function options(maxAge: number): SessionCookie['options'] {
  return { httpOnly: true, secure: process.env.NODE_ENV === 'production', sameSite: 'lax', path: '/', maxAge };
}

export function sessionCookies(tokens: AuthTokensDto): SessionCookie[] {
  return [
    { name: ACCESS_COOKIE, value: tokens.accessToken, options: options(Math.max(tokens.accessTokenExpiresIn - ACCESS_MARGIN_SECONDS, 1)) },
    { name: REFRESH_COOKIE, value: tokens.refreshToken, options: options(SESSION_MAX_AGE_SECONDS) },
  ];
}

// Même nom, même chemin, durée nulle : le navigateur supprime le cookie.
export function clearedSessionCookies(): SessionCookie[] {
  return [ACCESS_COOKIE, REFRESH_COOKIE].map((name) => ({ name, value: '', options: options(0) }));
}

// Chemin interne vers lequel revenir après la connexion ; tout le reste (URL absolue, `//hôte`) est ignoré.
export function safeReturnPath(path: string | null | undefined): string {
  return path && path.startsWith('/') && !path.startsWith('//') && !path.startsWith('/\\') ? path : '/';
}
