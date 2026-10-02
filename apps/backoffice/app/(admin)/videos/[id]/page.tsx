import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { CommentsTable } from '@/components/comments-table';
import { RemoveContent } from '@/components/remove-content';
import { HlsPlayer } from '@/components/hls-player';
import { Thumbnail } from '@/components/thumbnail';
import { UserAvatar } from '@/components/user-avatar';
import { VideoStatusBadge } from '@/components/video-status-badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { removeVideo } from '@/controllers/moderation.actions';
import { formatDateTime, formatNumber } from '@/lib/format';
import { listComments } from '@/models/comments.model';
import { getVideo } from '@/models/videos.model';

export const metadata: Metadata = { title: 'Vidéo' };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const RECENT_COMMENTS = 20;

export default async function VideoPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID.test(id)) notFound();
  const [video, comments] = await Promise.all([getVideo(id), listComments({ videoId: id, limit: RECENT_COMMENTS })]);
  if (!video) notFound();

  const figures = [
    ['Vues', video.viewsCount],
    ['Likes', video.likesCount],
    ['Commentaires', video.commentsCount],
    ['Favoris', video.favoritesCount],
    ['Republications', video.repostsCount],
    ['Partages', video.sharesCount],
  ] as const;

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-start gap-6">
        {video.status === 'ready' && video.hlsUrl ? (
          <HlsPlayer src={video.hlsUrl} poster={video.thumbnailUrl} />
        ) : (
          <Thumbnail url={video.thumbnailUrl} className="w-40" />
        )}

        <div className="flex min-w-64 flex-1 flex-col gap-4">
          <div className="flex items-center gap-3">
            <VideoStatusBadge status={video.status} />
            <span className="text-sm text-muted-foreground">{formatDateTime(video.createdAt)}</span>
          </div>
          <p className="whitespace-pre-wrap">{video.description || <em className="text-muted-foreground">Sans description</em>}</p>
          <Link href={`/users/${video.author.id}`} className="flex w-fit items-center gap-2">
            <UserAvatar user={video.author} size="sm" />
            <span className="font-medium">{video.author.displayName}</span>
            <span className="text-muted-foreground">@{video.author.username}</span>
          </Link>
          <dl className="grid grid-cols-3 gap-3 sm:grid-cols-6">
            {figures.map(([label, value]) => (
              <div key={label}>
                <dt className="text-xs text-muted-foreground">{label}</dt>
                <dd className="font-semibold tabular-nums">{formatNumber(value)}</dd>
              </div>
            ))}
          </dl>
          <code className="text-xs text-muted-foreground">{video.id}</code>
          <div>
            <RemoveContent
              size="default"
              label="Supprimer la vidéo"
              title="Supprimer cette vidéo ?"
              description="La vidéo, ses likes, commentaires, favoris et notifications sont supprimés définitivement, puis ses fichiers. Son auteur est prévenu avec le motif choisi."
              action={removeVideo.bind(null, video.id, '/videos')}
            />
          </div>
        </div>
      </div>

      <Card>
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle>Commentaires récents</CardTitle>
          {comments.nextCursor && (
            <Button variant="link" asChild>
              <Link href={`/comments?videoId=${video.id}`}>Tous les commentaires</Link>
            </Button>
          )}
        </CardHeader>
        <CardContent>
          <CommentsTable comments={comments.items} showVideo={false} />
        </CardContent>
      </Card>
    </div>
  );
}
