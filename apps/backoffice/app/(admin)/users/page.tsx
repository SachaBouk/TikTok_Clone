import type { Metadata } from 'next';
import Link from 'next/link';
import { Pagination } from '@/components/pagination';
import { UserAvatar } from '@/components/user-avatar';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { formatDateTime, formatNumber, withQuery } from '@/lib/format';
import { listUsers } from '@/models/users.model';

export const metadata: Metadata = { title: 'Comptes' };

export default async function UsersPage({ searchParams }: { searchParams: Promise<{ q?: string; curseur?: string }> }) {
  const { q, curseur } = await searchParams;
  const page = await listUsers({ q, cursor: curseur });

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-semibold">Comptes</h1>
      <form className="flex max-w-md gap-2" action="/users">
        <Input name="q" defaultValue={q} placeholder="Pseudo, nom ou identifiant" aria-label="Rechercher un compte" />
        <Button type="submit" variant="outline">
          Rechercher
        </Button>
      </form>

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
          {page.items.map((user) => (
            <TableRow key={user.id}>
              <TableCell>
                <Link href={`/users/${user.id}`} className="flex items-center gap-3">
                  <UserAvatar user={user} />
                  <span className="flex flex-col">
                    <span className="flex items-center gap-2 font-medium">
                      {user.displayName}
                      {user.role === 'admin' && <Badge variant="secondary">Admin</Badge>}
                    </span>
                    <span className="text-muted-foreground">@{user.username}</span>
                  </span>
                </Link>
              </TableCell>
              <TableCell className="text-right tabular-nums">{formatNumber(user.videosCount)}</TableCell>
              <TableCell className="text-right tabular-nums">{formatNumber(user.followersCount)}</TableCell>
              <TableCell className="text-right tabular-nums">{formatNumber(user.tokenBalance)}</TableCell>
              <TableCell className="text-muted-foreground">{formatDateTime(user.createdAt)}</TableCell>
            </TableRow>
          ))}
          {page.items.length === 0 && (
            <TableRow>
              <TableCell colSpan={5} className="py-8 text-center text-muted-foreground">
                Aucun compte{q ? ` pour « ${q} »` : ''}.
              </TableCell>
            </TableRow>
          )}
        </TableBody>
      </Table>

      <Pagination
        onFirstPage={!curseur}
        firstHref={withQuery('/users', { q })}
        nextHref={page.nextCursor ? withQuery('/users', { q, curseur: page.nextCursor }) : null}
      />
    </div>
  );
}
