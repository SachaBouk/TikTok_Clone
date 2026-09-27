import Link from 'next/link';

export default function NotFound() {
  return (
    <div className="flex flex-col gap-2">
      <h1 className="text-2xl font-semibold">Introuvable</h1>
      <p className="text-muted-foreground">Ce contenu n’existe pas ou a été supprimé.</p>
      <Link href="/" className="text-sm underline">
        Retour au tableau de bord
      </Link>
    </div>
  );
}
