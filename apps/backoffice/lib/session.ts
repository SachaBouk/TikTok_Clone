import 'server-only';
import type { AuthTokensDto } from '@repo/shared';
import { cookies } from 'next/headers';
import { clearedSessionCookies, REFRESH_COOKIE, sessionCookies } from './session-cookies';

// Écriture de la session, possible seulement dans une Server Action ou un Route Handler.

export async function saveSession(tokens: AuthTokensDto): Promise<void> {
  const store = await cookies();
  for (const cookie of sessionCookies(tokens)) store.set(cookie.name, cookie.value, cookie.options);
}

// Efface la session et renvoie le refresh token qu'elle portait (à révoquer auprès de l'API).
export async function clearSession(): Promise<string | undefined> {
  const store = await cookies();
  const refreshToken = store.get(REFRESH_COOKIE)?.value;
  for (const cookie of clearedSessionCookies()) store.set(cookie.name, cookie.value, cookie.options);
  return refreshToken;
}
