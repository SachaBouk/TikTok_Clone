import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { Thumbnail } from '@/components/thumbnail';
import { UserAvatar } from '@/components/user-avatar';
import { VideoStatusBadge } from '@/components/video-status-badge';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { formatDateTime, formatNumber } from '@/lib/format';
import { getUser } from '@/models/users.model';
import { listVideos } from '@/models/videos.model';

export const metadata: Metadata = { title: 'Compte' };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const RECENT_VIDEOS = 12;

export default async function UserPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID.test(id)) notFound();
  const [user, videos] = await Promise.all([getUser(id), listVideos({ userId: id, limit: RECENT_VIDEOS })]);
  if (!user) notFound();

  const figures = [
    ['Vidéos', user.videosCount],
    ['Abonnés', user.followersCount],
    ['Abonnements', user.followingCount],
  ] as const;

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center gap-4">
        <UserAvatar user={user} size="lg" />
        <div className="flex-1">
          <h1 className="flex items-center gap-2 text-2xl font-semibold">
            {user.displayName}
            {user.role === 'admin' && <Badge variant="secondary">Admin</Badge>}
          </h1>
          <p className="text-muted-foreground">@{user.username}</p>
        </div>
        <Button variant="outline" asChild>
          <Link href={`/comments?userId=${user.id}`}>Ses commentaires</Link>
        </Button>
      </div>

      <Card>
        <CardContent className="grid gap-4 sm:grid-cols-4">
          {figures.map(([label, value]) => (
            <div key={label}>
              <div className="text-sm text-muted-foreground">{label}</div>
              <div className="text-xl font-semibold tabular-nums">{formatNumber(value)}</div>
            </div>
          ))}
          <div>
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
    </div>
  );
}
