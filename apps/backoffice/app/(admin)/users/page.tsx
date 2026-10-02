import type { Metadata } from 'next';
import Link from 'next/link';
import type { AdminUserDto } from '@repo/shared';
import { Pagination } from '@/components/pagination';
import { UserAvatar } from '@/components/user-avatar';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { formatDateTime, formatNumber, withQuery } from '@/lib/format';
import { listUsers } from '@/models/users.model';

export const metadata: Metadata = { title: 'Comptes' };

// Comptes : tous (recherche par pseudo, nom ou identifiant), ou les seuls comptes suspendus (ADR-037), du plus récemment
// suspendu au plus ancien, avec le motif et l'administrateur.
export default async function UsersPage({ searchParams }: { searchParams: Promise<{ q?: string; curseur?: string; suspendus?: string }> }) {
  const { q, curseur, suspendus } = await searchParams;
  const suspendedOnly = suspendus === '1';
  const page = await listUsers({ q: suspendedOnly ? undefined : q, cursor: curseur, suspended: suspendedOnly });
  const filter = suspendedOnly ? { suspendus: '1' } : { q };

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-semibold">Comptes</h1>
      <div className="flex flex-wrap items-center gap-2">
        <Button variant={suspendedOnly ? 'outline' : 'default'} size="sm" asChild>
          <Link href="/users" aria-current={suspendedOnly ? undefined : 'page'}>
            Tous
          </Link>
        </Button>
        <Button variant={suspendedOnly ? 'default' : 'outline'} size="sm" asChild>
          <Link href="/users?suspendus=1" aria-current={suspendedOnly ? 'page' : undefined}>
            Suspendus
          </Link>
        </Button>
        {!suspendedOnly && (
          <form className="flex max-w-md flex-1 gap-2" action="/users">
            <Input name="q" defaultValue={q} placeholder="Pseudo, nom ou identifiant" aria-label="Rechercher un compte" />
            <Button type="submit" variant="outline">
              Rechercher
            </Button>
          </form>
        )}
      </div>

      {suspendedOnly ? <SuspendedTable users={page.items} /> : <AccountsTable users={page.items} q={q} />}

      <Pagination
        onFirstPage={!curseur}
        firstHref={withQuery('/users', filter)}
        nextHref={page.nextCursor ? withQuery('/users', { ...filter, curseur: page.nextCursor }) : null}
      />
    </div>
  );
}

function AccountCell({ user }: { user: AdminUserDto }) {
  return (
    <Link href={`/users/${user.id}`} className="flex items-center gap-3">
      <UserAvatar user={user} />
      <span className="flex flex-col">
        <span className="flex items-center gap-2 font-medium">
          {user.displayName}
          {user.role === 'admin' && <Badge variant="secondary">Admin</Badge>}
          {user.suspension && <Badge variant="destructive">Suspendu</Badge>}
        </span>
        <span className="text-muted-foreground">@{user.username}</span>
      </span>
    </Link>
  );
}

function AccountsTable({ users, q }: { users: AdminUserDto[]; q?: string }) {
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Compte</TableHead>
          <TableHead className="text-right">Vidéos</TableHead>
          <TableHead className="text-right">Abonnés</TableHead>
          <TableHead className="text-right">Jetons</TableHead>
          <TableHead>Inscription</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {users.map((user) => (
          <TableRow key={user.id}>
            <TableCell>
              <AccountCell user={user} />
            </TableCell>
            <TableCell className="text-right tabular-nums">{formatNumber(user.videosCount)}</TableCell>
            <TableCell className="text-right tabular-nums">{formatNumber(user.followersCount)}</TableCell>
            <TableCell className="text-right tabular-nums">{formatNumber(user.tokenBalance)}</TableCell>
            <TableCell className="text-muted-foreground">{formatDateTime(user.createdAt)}</TableCell>
          </TableRow>
        ))}
        {users.length === 0 && (
          <TableRow>
            <TableCell colSpan={5} className="py-8 text-center text-muted-foreground">
              Aucun compte{q ? ` pour « ${q} »` : ''}.
            </TableCell>
          </TableRow>
        )}
      </TableBody>
    </Table>
  );
}

// Comptes suspendus : date, motif interne et administrateur ; la levée se fait depuis la fiche du compte.
function SuspendedTable({ users }: { users: AdminUserDto[] }) {
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Compte</TableHead>
          <TableHead>Suspendu le</TableHead>
          <TableHead>Motif</TableHead>
          <TableHead>Par</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {users.map((user) => (
          <TableRow key={user.id}>
            <TableCell>
              <AccountCell user={user} />
            </TableCell>
            <TableCell className="text-muted-foreground">{user.suspension ? formatDateTime(user.suspension.suspendedAt) : '—'}</TableCell>
            <TableCell className="max-w-sm whitespace-normal">{user.suspension?.reason ?? '—'}</TableCell>
            <TableCell>
              {user.suspension?.suspendedBy ? (
                <Link href={`/users/${user.suspension.suspendedBy.id}`} className="hover:underline">
                  @{user.suspension.suspendedBy.username}
                </Link>
              ) : (
                <span className="text-muted-foreground">Compte supprimé</span>
              )}
            </TableCell>
          </TableRow>
        ))}
        {users.length === 0 && (
          <TableRow>
            <TableCell colSpan={4} className="py-8 text-center text-muted-foreground">
              Aucun compte suspendu.
            </TableCell>
          </TableRow>
        )}
      </TableBody>
    </Table>
  );
}
