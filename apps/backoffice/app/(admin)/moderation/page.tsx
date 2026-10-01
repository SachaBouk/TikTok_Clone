import type { Metadata } from 'next';
import Link from 'next/link';
import type { AdminModerationActionDto } from '@repo/shared';
import { FilterChip } from '@/components/filter-chip';
import { Pagination } from '@/components/pagination';
import { Badge } from '@/components/ui/badge';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { formatDateTime, formatNumber, withQuery } from '@/lib/format';
import { MODERATION_ACTION_LABELS, REPORT_REASON_LABELS, REPORT_TARGET_LABELS } from '@/lib/report-labels';
import { listModerationActions } from '@/models/moderation.model';
import { getUser } from '@/models/users.model';

export const metadata: Metadata = { title: 'Journal' };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Journal de modération (ADR-038) : chaque suppression, suspension, levée et classement sans suite, du plus récent au
// plus ancien. Pseudos et texte sont copiés : le journal survit aux suppressions.
export default async function ModerationPage({ searchParams }: { searchParams: Promise<{ userId?: string; curseur?: string }> }) {
  const { userId, curseur } = await searchParams;
  const filterId = userId && UUID.test(userId) ? userId : undefined;
  const [page, account] = await Promise.all([listModerationActions({ userId: filterId, cursor: curseur }), filterId ? getUser(filterId) : null]);

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-semibold">Journal de modération</h1>
      <p className="text-sm text-muted-foreground">Actions des administrateurs, de la plus récente à la plus ancienne.</p>
      {filterId && (
        <div className="flex gap-2">
          <FilterChip label={account ? `Compte : @${account.username}` : 'Un compte'} clearHref="/moderation" />
        </div>
      )}
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Date, par</TableHead>
            <TableHead>Action</TableHead>
            <TableHead>Compte visé</TableHead>
            <TableHead>Contenu</TableHead>
            <TableHead>Motif</TableHead>
            <TableHead className="text-right">Signalements clos</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {page.items.map((action) => (
            <TableRow key={action.id}>
              <TableCell>
                <span className="flex flex-col text-sm">
                  <span className="text-muted-foreground">{formatDateTime(action.createdAt)}</span>
                  <Account user={action.admin} username={action.adminUsername} />
                </span>
              </TableCell>
              <TableCell>
                <Badge variant={action.action === 'suspensionLifted' || action.action === 'reportsDismissed' ? 'secondary' : 'destructive'}>
                  {MODERATION_ACTION_LABELS[action.action]}
                </Badge>
              </TableCell>
              <TableCell>
                <Account user={action.targetUser} username={action.targetUsername} />
              </TableCell>
              <TableCell className="min-w-48 max-w-xs whitespace-normal">
                {action.targetType === 'account' ? (
                  <span className="text-muted-foreground">—</span>
                ) : (
                  <span className="flex flex-col gap-1">
                    <span className="text-xs text-muted-foreground">{REPORT_TARGET_LABELS[action.targetType]}</span>
                    <span className="line-clamp-2 text-sm">{action.excerpt ?? '—'}</span>
                  </span>
                )}
              </TableCell>
              <TableCell className="max-w-xs whitespace-normal">{reasonOf(action)}</TableCell>
              <TableCell className="text-right tabular-nums">
                {action.reportsClosed > 0 ? (
                  <Link href={`/reports/${action.targetType}/${action.targetId}`} className="hover:underline">
                    {formatNumber(action.reportsClosed)}
                  </Link>
                ) : (
                  '—'
                )}
              </TableCell>
            </TableRow>
          ))}
          {page.items.length === 0 && (
            <TableRow>
              <TableCell colSpan={6} className="py-8 text-center text-muted-foreground">
                Aucune action.
              </TableCell>
            </TableRow>
          )}
        </TableBody>
      </Table>
      <Pagination
        onFirstPage={!curseur}
        firstHref={withQuery('/moderation', { userId: filterId })}
        nextHref={page.nextCursor ? withQuery('/moderation', { userId: filterId, curseur: page.nextCursor }) : null}
      />
    </div>
  );
}

// Suppression : motif de la liste (annoncé à l'auteur) ; suspension : motif saisi (interne).
function reasonOf(action: AdminModerationActionDto): string {
  if (action.reason) return REPORT_REASON_LABELS[action.reason];
  return action.note ?? '—';
}

// Lien vers la fiche du compte, ou son pseudo d'alors s'il a été supprimé.
function Account({ user, username }: { user?: { id: string; username: string }; username: string | null }) {
  if (user) {
    return (
      <Link href={`/users/${user.id}`} className="hover:underline">
        @{user.username}
      </Link>
    );
  }
  return <span className="text-muted-foreground">{username ? `@${username} (supprimé)` : '—'}</span>;
}
