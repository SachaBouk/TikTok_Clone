'use client';

import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Button } from '@/components/ui/button';

// Erreur de l'API (hors session) ou API injoignable pendant le rendu d'une page.
export default function AdminError({ reset }: { error: Error; reset: () => void }) {
  return (
    <Alert variant="destructive" className="max-w-xl">
      <AlertTitle>Impossible de charger la page</AlertTitle>
      <AlertDescription>
        <p>L’API a renvoyé une erreur ou est injoignable.</p>
        <Button variant="outline" size="sm" className="mt-3" onClick={reset}>
          Réessayer
        </Button>
      </AlertDescription>
    </Alert>
  );
}
