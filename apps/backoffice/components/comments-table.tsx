import Link from 'next/link';
import type { AdminCommentDto } from '@repo/shared';
import { RemoveContent } from '@/components/remove-content';
import { Thumbnail } from '@/components/thumbnail';
import { UserAvatar } from '@/components/user-avatar';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { removeComment } from '@/controllers/moderation.actions';
import { formatDateTime } from '@/lib/format';

// Liste de commentaires avec leur auteur, leur vidéo et le bouton de suppression (liste et page d'une vidéo).
export function CommentsTable({ comments, showVideo = true }: { comments: AdminCommentDto[]; showVideo?: boolean }) {
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Auteur</TableHead>
          <TableHead>Commentaire</TableHead>
          {showVideo && <TableHead>Vidéo</TableHead>}
          <TableHead>Date</TableHead>
          <TableHead />
        </TableRow>
      </TableHeader>
      <TableBody>
        {comments.map((comment) => (
          <TableRow key={comment.id}>
            <TableCell>
              <Link href={`/users/${comment.author.id}`} className="flex items-center gap-2">
                <UserAvatar user={comment.author} size="sm" />
                <span>@{comment.author.username}</span>
              </Link>
            </TableCell>
            <TableCell className="max-w-md whitespace-normal">{comment.content}</TableCell>
            {showVideo && (
              <TableCell>
                <Link href={`/videos/${comment.video.id}`} aria-label="Voir la vidéo">
                  <Thumbnail url={comment.video.thumbnailUrl} className="w-8" />
                </Link>
              </TableCell>
            )}
            <TableCell className="text-muted-foreground">{formatDateTime(comment.createdAt)}</TableCell>
            <TableCell className="text-right">
              <RemoveContent
                label="Supprimer"
                title="Supprimer ce commentaire ?"
                description={`Le commentaire de @${comment.author.username} et sa notification seront supprimés définitivement. Son auteur est prévenu avec le motif choisi.`}
                action={removeComment.bind(null, comment.id)}
              />
            </TableCell>
          </TableRow>
        ))}
        {comments.length === 0 && (
          <TableRow>
            <TableCell colSpan={showVideo ? 5 : 4} className="py-8 text-center text-muted-foreground">
              Aucun commentaire.
            </TableCell>
          </TableRow>
        )}
      </TableBody>
    </Table>
  );
}
