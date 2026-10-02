import { NextResponse, type NextRequest } from 'next/server';
import { refreshSession } from '@/models/auth.model';
import { ACCESS_COOKIE, clearedSessionCookies, REFRESH_COOKIE, sessionCookies } from '@/lib/session-cookies';
import { createRefresher } from '@/lib/token-refresh';

// Rafraîchissement dédupliqué, partagé par toutes les requêtes du processus (voir lib/token-refresh).
const refreshOnce = createRefresher(refreshSession);

// Proxy (ex-middleware, Next 16) : avant chaque page ou Server Action, garantit un access token valide.
// Les cookies ne peuvent pas être écrits pendant le rendu d'une page : c'est donc ici que la session est
// rafraîchie, et les nouveaux jetons sont passés à la requête en cours comme au navigateur.
// Le rôle administrateur, lui, est vérifié par l'API à chaque appel (403 : fin de session, app/auth/fin).
export async function proxy(request: NextRequest) {
  if (request.cookies.has(ACCESS_COOKIE)) return NextResponse.next();

  const refreshToken = request.cookies.get(REFRESH_COOKIE)?.value;
  if (!refreshToken) return toLogin(request, null);

  let outcome;
  try {
    outcome = await refreshOnce(refreshToken);
  } catch {
    // Session gardée : rien n'a été consommé, la prochaine requête réessaiera.
    return new NextResponse('API injoignable : réessayez dans un instant.', {
      status: 503,
      headers: { 'Content-Type': 'text/plain; charset=utf-8' },
    });
  }
  if (outcome.kind === 'rejected') return toLogin(request, 'session');

  const cookies = sessionCookies(outcome.tokens);
  for (const cookie of cookies) request.cookies.set(cookie.name, cookie.value);
  const response = NextResponse.next({ request: { headers: request.headers } });
  for (const cookie of cookies) response.cookies.set(cookie.name, cookie.value, cookie.options);
  return response;
}

function toLogin(request: NextRequest, reason: 'session' | null): NextResponse {
  const url = new URL('/login', request.url);
  const { pathname, search } = request.nextUrl;
  if (pathname !== '/') url.searchParams.set('suite', `${pathname}${search}`);
  if (reason) url.searchParams.set('raison', reason);
  const response = NextResponse.redirect(url);
  for (const cookie of clearedSessionCookies()) response.cookies.set(cookie.name, cookie.value, cookie.options);
  return response;
}

export const config = {
  // Tout sauf la connexion, la fin de session et les fichiers de Next.
  matcher: ['/((?!login|auth/|_next/static|_next/image|favicon.ico).*)'],
};
