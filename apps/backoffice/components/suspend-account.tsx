'use client';

import { useState, useTransition } from 'react';
import { suspendAccount } from '@/controllers/moderation.actions';
import { MAX_SUSPENSION_REASON_LENGTH } from '@/lib/moderation-rules';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/ui/alert-dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';

// Suspension d'un compte (ADR-037), avec un motif interne obligatoire, confirmée dans une alerte.
export function SuspendAccount({ userId, username }: { userId: string; username: string }) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function confirm(event: React.MouseEvent) {
    event.preventDefault();
    startTransition(async () => {
      const result = await suspendAccount(userId, reason);
      setError(result.error);
      if (!result.error) {
        setOpen(false);
        setReason('');
      }
    });
  }

  return (
    <AlertDialog open={open} onOpenChange={(next) => (setOpen(next), setError(null))}>
      <AlertDialogTrigger asChild>
        <Button variant="destructive">Suspendre</Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Suspendre @{username} ?</AlertDialogTitle>
          <AlertDialogDescription>
            Le compte est déconnecté de tous ses appareils et ne peut plus se connecter. Son profil, ses vidéos, ses commentaires et ses messages
            disparaissent pour les autres, jusqu’à la levée de la suspension. Rien n’est supprimé.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <div className="flex flex-col gap-2">
          <Label htmlFor="suspension-reason">Motif (interne, jamais montré à la personne)</Label>
          <Textarea
            id="suspension-reason"
            value={reason}
            maxLength={MAX_SUSPENSION_REASON_LENGTH}
            onChange={(event) => setReason(event.target.value)}
            placeholder="Spam répété dans les commentaires…"
            disabled={pending}
          />
        </div>
        {error && <p className="text-sm text-destructive">{error}</p>}
        <AlertDialogFooter>
          <AlertDialogCancel disabled={pending}>Annuler</AlertDialogCancel>
          <AlertDialogAction variant="destructive" onClick={confirm} disabled={pending || !reason.trim()}>
            {pending ? 'Suspension…' : 'Suspendre le compte'}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
