import { FilmIcon } from 'lucide-react';

// Miniature verticale (9:16) servie par le stockage public (le CDN en production).
export function Thumbnail({ url, className = 'w-12' }: { url: string | null; className?: string }) {
  return (
    <div className={`${className} aspect-[9/16] shrink-0 overflow-hidden rounded-md bg-muted`}>
      {url ? (
        // Pas de `next/image` : les miniatures viennent du CDN (MinIO en local), sans optimisation par le serveur Next.
        // eslint-disable-next-line @next/next/no-img-element
        <img src={url} alt="" className="size-full object-cover" loading="lazy" />
      ) : (
        <div className="flex size-full items-center justify-center text-muted-foreground">
          <FilmIcon className="size-4" />
        </div>
      )}
    </div>
  );
}
