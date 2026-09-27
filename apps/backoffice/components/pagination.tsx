import Link from 'next/link';
import { Button } from '@/components/ui/button';

// Pagination par curseur (l'API renvoie `nextCursor`) : page suivante, ou retour au début.
export function Pagination({ firstHref, nextHref, onFirstPage }: { firstHref: string; nextHref: string | null; onFirstPage: boolean }) {
  if (onFirstPage && !nextHref) return null;
  return (
    <div className="flex justify-end gap-2">
      {!onFirstPage && (
        <Button variant="outline" size="sm" asChild>
          <Link href={firstHref}>Revenir au début</Link>
        </Button>
      )}
      {nextHref && (
        <Button variant="outline" size="sm" asChild>
          <Link href={nextHref}>Page suivante</Link>
        </Button>
      )}
    </div>
  );
}
