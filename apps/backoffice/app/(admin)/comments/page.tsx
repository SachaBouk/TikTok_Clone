import type { Metadata } from 'next';
import { CommentsTable } from '@/components/comments-table';
import { FilterChip } from '@/components/filter-chip';
import { Pagination } from '@/components/pagination';
import { withQuery } from '@/lib/format';
import { listComments } from '@/models/comments.model';
import { getUser } from '@/models/users.model';

export const metadata: Metadata = { title: 'Commentaires' };

export default async function CommentsPage({ searchParams }: { searchParams: Promise<{ videoId?: string; userId?: string; curseur?: string }> }) {
  const { videoId, userId, curseur } = await searchParams;
  const [page, author] = await Promise.all([listComments({ videoId, userId, cursor: curseur }), userId ? getUser(userId) : null]);

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-semibold">Commentaires</h1>
      <p className="text-sm text-muted-foreground">Du plus récent au plus ancien, sur toutes les vidéos.</p>
      {(videoId || userId) && (
        <div className="flex gap-2">
          {userId && <FilterChip label={author ? `Auteur : @${author.username}` : 'Un auteur'} clearHref={withQuery('/comments', { videoId })} />}
          {videoId && <FilterChip label="Une vidéo" clearHref={withQuery('/comments', { userId })} />}
        </div>
      )}
      <CommentsTable comments={page.items} />
      <Pagination
        onFirstPage={!curseur}
        firstHref={withQuery('/comments', { videoId, userId })}
        nextHref={page.nextCursor ? withQuery('/comments', { videoId, userId, curseur: page.nextCursor }) : null}
      />
    </div>
  );
}
