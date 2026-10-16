import type { Metadata } from 'next';
import Link from 'next/link';
import type { VideoStatus } from '@repo/shared';
import { FilterChip } from '@/components/filter-chip';
import { Pagination } from '@/components/pagination';
import { Thumbnail } from '@/components/thumbnail';
import { VIDEO_STATUS_LABELS, VideoStatusBadge, VideoVisibilityBadge } from '@/components/video-status-badge';
import { Button } from '@/components/ui/button';
import { NativeSelect, NativeSelectOption } from '@/components/ui/native-select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { formatDateTime, formatNumber, withQuery } from '@/lib/format';
import { getUser } from '@/models/users.model';
import { listVideos } from '@/models/videos.model';

export const metadata: Metadata = { title: 'Vidéos' };

const STATUSES = Object.keys(VIDEO_STATUS_LABELS) as VideoStatus[];

export default async function VideosPage({ searchParams }: { searchParams: Promise<{ status?: string; userId?: string; curseur?: string }> }) {
  const params = await searchParams;
  const status = STATUSES.find((value) => value === params.status);
  const { userId, curseur } = params;
  const [page, author] = await Promise.all([listVideos({ status, userId, cursor: curseur }), userId ? getUser(userId) : null]);

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-semibold">Vidéos</h1>
      <form className="flex flex-wrap items-center gap-2" action="/videos">
        {userId && <input type="hidden" name="userId" value={userId} />}
        <NativeSelect name="status" defaultValue={status ?? ''} aria-label="Statut">
          <NativeSelectOption value="">Tous les statuts</NativeSelectOption>
          {STATUSES.map((value) => (
            <NativeSelectOption key={value} value={value}>
              {VIDEO_STATUS_LABELS[value]}
            </NativeSelectOption>
          ))}
        </NativeSelect>
        <Button type="submit" variant="outline">
          Filtrer
        </Button>
        {userId && <FilterChip label={author ? `Auteur : @${author.username}` : 'Un auteur'} clearHref={withQuery('/videos', { status })} />}
      </form>

      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Vidéo</TableHead>
            <TableHead>Auteur</TableHead>
            <TableHead>Statut</TableHead>
            <TableHead className="text-right">Vues</TableHead>
            <TableHead className="text-right">Likes</TableHead>
            <TableHead className="text-right">Commentaires</TableHead>
            <TableHead>Création</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {page.items.map((video) => (
            <TableRow key={video.id}>
              <TableCell>
                <Link href={`/videos/${video.id}`} className="flex items-center gap-3">
                  <Thumbnail url={video.thumbnailUrl} />
                  <span className="line-clamp-2 max-w-xs whitespace-normal">
                    {video.description || <em className="text-muted-foreground">Sans description</em>}
                  </span>
                </Link>
              </TableCell>
              <TableCell>
                <Link href={`/users/${video.author.id}`} className="hover:underline">
                  @{video.author.username}
                </Link>
              </TableCell>
              <TableCell>
                <div className="flex gap-1">
                  <VideoStatusBadge status={video.status} />
                  <VideoVisibilityBadge visibility={video.visibility} />
                </div>
              </TableCell>
              <TableCell className="text-right tabular-nums">{formatNumber(video.viewsCount)}</TableCell>
              <TableCell className="text-right tabular-nums">{formatNumber(video.likesCount)}</TableCell>
              <TableCell className="text-right tabular-nums">{formatNumber(video.commentsCount)}</TableCell>
              <TableCell className="text-muted-foreground">{formatDateTime(video.createdAt)}</TableCell>
            </TableRow>
          ))}
          {page.items.length === 0 && (
            <TableRow>
              <TableCell colSpan={7} className="py-8 text-center text-muted-foreground">
                Aucune vidéo.
              </TableCell>
            </TableRow>
          )}
        </TableBody>
      </Table>

      <Pagination
        onFirstPage={!curseur}
        firstHref={withQuery('/videos', { status, userId })}
        nextHref={page.nextCursor ? withQuery('/videos', { status, userId, curseur: page.nextCursor }) : null}
      />
    </div>
  );
}
