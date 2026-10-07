import Link from 'next/link';
import type { AdminGiftDto, UserSummaryDto } from '@repo/shared';
import { Thumbnail } from '@/components/thumbnail';
import { UserAvatar } from '@/components/user-avatar';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { formatDateTime, formatNumber } from '@/lib/format';

// Journal des cadeaux (page « Cadeaux » et fiche d'un compte, ADR-050) : débités du solde de l'expéditeur, crédités aux
// gains du créateur. Un compte ou une vidéo supprimés depuis restent dans le journal, anonymisés.
export function GiftsTable({ gifts }: { gifts: AdminGiftDto[] }) {
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Date</TableHead>
          <TableHead>Cadeau</TableHead>
          <TableHead className="text-right">Jetons</TableHead>
          <TableHead>Expéditeur</TableHead>
          <TableHead>Créateur</TableHead>
          <TableHead>Vidéo</TableHead>
          <TableHead className="text-right">Solde après</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {gifts.map((gift) => (
          <TableRow key={gift.id}>
            <TableCell className="text-muted-foreground">{formatDateTime(gift.createdAt)}</TableCell>
            <TableCell>
              <span className="flex items-center gap-2">
                <span aria-hidden>{gift.gift.emoji}</span>
                {gift.gift.name}
              </span>
            </TableCell>
            <TableCell className="text-right tabular-nums">{formatNumber(gift.amount)}</TableCell>
            <TableCell>
              <Account user={gift.sender} />
            </TableCell>
            <TableCell>
              <Account user={gift.recipient} />
            </TableCell>
            <TableCell>
              {gift.video ? (
                <Link href={`/videos/${gift.video.id}`} aria-label="Voir la vidéo">
                  <Thumbnail url={gift.video.thumbnailUrl} className="w-8" />
                </Link>
              ) : gift.videoId ? (
                <Link href={`/videos/${gift.videoId}`} className="text-sm text-muted-foreground underline-offset-4 hover:underline">
                  Non publiée
                </Link>
              ) : (
                <span className="text-sm text-muted-foreground">Supprimée</span>
              )}
            </TableCell>
            <TableCell className="text-right tabular-nums">{formatNumber(gift.senderBalanceAfter)}</TableCell>
          </TableRow>
        ))}
        {gifts.length === 0 && (
          <TableRow>
            <TableCell colSpan={7} className="py-8 text-center text-muted-foreground">
              Aucun cadeau.
            </TableCell>
          </TableRow>
        )}
      </TableBody>
    </Table>
  );
}

function Account({ user }: { user?: UserSummaryDto }) {
  if (!user) return <span className="text-muted-foreground">Compte supprimé</span>;
  return (
    <Link href={`/users/${user.id}`} className="flex items-center gap-2">
      <UserAvatar user={user} size="sm" />
      <span>@{user.username}</span>
    </Link>
  );
}
