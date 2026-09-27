import { NextResponse, type NextRequest } from 'next/server';
import { clearSession } from '@/lib/session';
import { logout } from '@/models/auth.model';

// Fin de session imposée par l'API pendant le rendu d'une page (401 : session expirée ou révoquée ;
// 403 : rôle administrateur retiré). Une page ne peut pas effacer les cookies : elle redirige ici.
export async function GET(request: NextRequest) {
  const refreshToken = await clearSession();
  if (refreshToken) await logout(refreshToken);
  const reason = request.nextUrl.searchParams.get('raison') === 'acces' ? 'acces' : 'session';
  return NextResponse.redirect(new URL(`/login?raison=${reason}`, request.url));
}
