import Link from 'next/link';
import { XIcon } from 'lucide-react';
import { Badge } from '@/components/ui/badge';

// Filtre actif d'une liste, retiré en un clic.
export function FilterChip({ label, clearHref }: { label: string; clearHref: string }) {
  return (
    <Badge variant="outline" asChild>
      <Link href={clearHref} aria-label={`Retirer le filtre ${label}`}>
        {label}
        <XIcon />
      </Link>
    </Badge>
  );
}
