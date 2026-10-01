import type { ReactNode } from 'react';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { NavLink } from '@/components/nav-link';
import { UserAvatar } from '@/components/user-avatar';
import { Button } from '@/components/ui/button';
import { logout } from '@/controllers/auth.actions';
import { ACCESS_COOKIE } from '@/lib/session-cookies';
import { getAdminSession } from '@/models/auth.model';
import { ApiError } from '@/lib/api-error';

// Gabarit des écrans d'administration : navigation et compte connecté. Chaque appel à l'API revérifie
// de toute façon le rôle : un rôle retiré renvoie à la connexion (app/auth/fin).
export default async function AdminLayout({ children }: { children: ReactNode }) {
  const accessToken = (await cookies()).get(ACCESS_COOKIE)?.value;
  if (!accessToken) redirect('/auth/fin?raison=session');
  const admin = await getAdminSession(accessToken).catch((error: unknown) => {
    if (error instanceof ApiError && error.status === 401) redirect('/auth/fin?raison=session');
    if (error instanceof ApiError && (error.status === 403 || error.status === 404)) redirect('/auth/fin?raison=acces');
    throw error;
  });

  return (
    <div className="flex min-h-screen flex-col">
      <header className="border-b">
        <div className="mx-auto flex max-w-6xl flex-wrap items-center gap-4 px-4 py-3">
          <span className="font-semibold">Backoffice</span>
          <nav className="flex flex-1 flex-wrap gap-1">
            <NavLink href="/">Tableau de bord</NavLink>
            <NavLink href="/users">Comptes</NavLink>
            <NavLink href="/videos">Vidéos</NavLink>
            <NavLink href="/comments">Commentaires</NavLink>
            <NavLink href="/reports">Signalements</NavLink>
            <NavLink href="/tokens">Jetons</NavLink>
          </nav>
          <div className="flex items-center gap-2 text-sm">
            <UserAvatar user={admin} size="sm" />
            <span className="text-muted-foreground">@{admin.username}</span>
            <form action={logout}>
              <Button variant="ghost" size="sm" type="submit">
                Se déconnecter
              </Button>
            </form>
          </div>
        </div>
      </header>
      <main className="mx-auto w-full max-w-6xl flex-1 px-4 py-6">{children}</main>
    </div>
  );
}
