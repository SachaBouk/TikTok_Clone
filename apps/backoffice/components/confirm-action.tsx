'use client';

import { useState, useTransition } from 'react';
import type { ActionResult } from '@/controllers/moderation.actions';
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

// Action de modération confirmée dans une alerte. `action` est une Server Action liée à sa cible.
// `destructive` (par défaut) : suppression irréversible ; sinon, action réversible (lever une suspension).
export function ConfirmAction({
  label,
  title,
  description,
  confirmLabel,
  action,
  size = 'sm',
  destructive = true,
  pendingLabel = 'Suppression…',
}: {
  label: string;
  title: string;
  description: string;
  confirmLabel: string;
  action: () => Promise<ActionResult>;
  size?: 'sm' | 'default';
  destructive?: boolean;
  pendingLabel?: string;
}) {
  const [open, setOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function confirm(event: React.MouseEvent) {
    event.preventDefault();
    startTransition(async () => {
      const result = await action();
      setError(result?.error ?? null);
      if (!result?.error) setOpen(false);
    });
  }

  return (
    <AlertDialog open={open} onOpenChange={(next) => (setOpen(next), setError(null))}>
      <AlertDialogTrigger asChild>
        <Button variant={destructive ? 'destructive' : 'outline'} size={size}>
          {label}
        </Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{title}</AlertDialogTitle>
          <AlertDialogDescription>{description}</AlertDialogDescription>
        </AlertDialogHeader>
        {error && <p className="text-sm text-destructive">{error}</p>}
        <AlertDialogFooter>
          <AlertDialogCancel disabled={pending}>Annuler</AlertDialogCancel>
          <AlertDialogAction variant={destructive ? 'destructive' : 'default'} onClick={confirm} disabled={pending}>
            {pending ? pendingLabel : confirmLabel}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
