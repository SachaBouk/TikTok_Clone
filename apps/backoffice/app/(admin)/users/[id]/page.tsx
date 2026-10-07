import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { ConfirmAction } from '@/components/confirm-action';
import { SuspendAccount } from '@/components/suspend-account';
import { Thumbnail } from '@/components/thumbnail';
import { UserAvatar } from '@/components/user-avatar';
import { VideoStatusBadge } from '@/components/video-status-badge';
import { WalletTransactionsTable } from '@/components/wallet-transactions-table';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { liftAccountSuspension } from '@/controllers/moderation.actions';
import { formatDateTime, formatNumber } from '@/lib/format';
import { getUser } from '@/models/users.model';
import { listVideos } from '@/models/videos.model';
import { listWalletTransactions } from '@/models/wallet.model';

export const metadata: Metadata = { title: 'Compte' };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const RECENT_VIDEOS = 12;
const RECENT_TRANSACTIONS = 10;

export default async function UserPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID.test(id)) notFound();
  const [user, videos, transactions] = await Promise.all([
    getUser(id),
    listVideos({ userId: id, limit: RECENT_VIDEOS }),
    listWalletTransactions({ userId: id, limit: RECENT_TRANSACTIONS }),
  ]);
  if (!user) notFound();

  const figures = [
    ['Vidéos', user.videosCount],
    ['Abonnés', user.followersCount],
    ['Abonnements', user.followingCount],
    ['Jetons', user.tokenBalance],
    // Jetons reçus en cadeaux (ADR-050), non dépensables.
    ['Gains', user.tokenEarned],
  ] as const;

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center gap-4">
        <UserAvatar user={user} size="lg" />
        <div className="flex-1">
          <h1 className="flex items-center gap-2 text-2xl font-semibold">
            {user.displayName}
            {user.role === 'admin' && <Badge variant="secondary">Admin</Badge>}
            {user.suspension && <Badge variant="destructive">Suspendu</Badge>}
          </h1>
          <p className="text-muted-foreground">@{user.username}</p>
        </div>
        <Button variant="outline" asChild>
          <Link href={`/comments?userId=${user.id}`}>Ses commentaires</Link>
        </Button>
        <Button variant="outline" asChild>
          <Link href={`/moderation?userId=${user.id}`}>Journal de modération</Link>
        </Button>
        <Button variant="outline" asChild>
          <Link href={`/gifts?userId=${user.id}`}>Ses cadeaux</Link>
        </Button>
        {/* Un administrateur ne peut pas être suspendu : retirer d'abord son rôle (pnpm admin:revoke). */}
        {!user.suspension && user.role !== 'admin' && <SuspendAccount userId={user.id} username={user.username} />}
      </div>

      {user.suspension && (
        <Alert variant="destructive">
          <AlertTitle>
            Compte suspendu le {formatDateTime(user.suspension.suspendedAt)}
            {user.suspension.suspendedBy ? ` par @${user.suspension.suspendedBy.username}` : ''}
          </AlertTitle>
          <AlertDescription className="flex flex-col gap-3">
            <p>Motif : {user.suspension.reason}</p>
            <p>Connexion refusée ; profil, vidéos, commentaires et messages masqués aux autres. Rien n’a été supprimé.</p>
            <div>
              <ConfirmAction
                label="Lever la suspension"
                title={`Lever la suspension de @${user.username} ?`}
                description="Le compte pourra se reconnecter, et ses contenus réapparaissent aussitôt."
                confirmLabel="Lever la suspension"
                pendingLabel="Levée…"
                destructive={false}
                action={liftAccountSuspension.bind(null, user.id)}
              />
            </div>
          </AlertDescription>
        </Alert>
      )}

      <Card>
        <CardContent className="grid gap-4 sm:grid-cols-4">
          {figures.map(([label, value]) => (
            <div key={label}>
              <div className="text-sm text-muted-foreground">{label}</div>
              <div className="text-xl font-semibold tabular-nums">{formatNumber(value)}</div>
            </div>
          ))}
          <div className="sm:col-span-4">
            <div className="text-sm text-muted-foreground">Inscription</div>
            <div className="font-medium">{formatDateTime(user.createdAt)}</div>
          </div>
          <div className="sm:col-span-4">
            <div className="text-sm text-muted-foreground">Bio</div>
            <p>{user.bio ?? '—'}</p>
          </div>
          <div className="sm:col-span-4">
            <div className="text-sm text-muted-foreground">Identifiant</div>
            <code className="text-sm">{user.id}</code>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle>Vidéos récentes</CardTitle>
          {videos.nextCursor && (
            <Button variant="link" asChild>
              <Link href={`/videos?userId=${user.id}`}>Toutes ses vidéos</Link>
            </Button>
          )}
        </CardHeader>
        <CardContent>
          {videos.items.length === 0 ? (
            <p className="text-sm text-muted-foreground">Aucune vidéo.</p>
          ) : (
            <ul className="grid grid-cols-3 gap-3 sm:grid-cols-6">
              {videos.items.map((video) => (
                <li key={video.id}>
                  <Link href={`/videos/${video.id}`} className="flex flex-col gap-1">
                    <Thumbnail url={video.thumbnailUrl} className="w-full" />
                    <VideoStatusBadge status={video.status} />
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle>Jetons</CardTitle>
          {transactions.nextCursor && (
            <Button variant="link" asChild>
              <Link href={`/tokens?userId=${user.id}`}>Tous ses mouvements</Link>
            </Button>
          )}
        </CardHeader>
        <CardContent>
          <WalletTransactionsTable transactions={transactions.items} showAccount={false} />
        </CardContent>
      </Card>
    </div>
  );
}
