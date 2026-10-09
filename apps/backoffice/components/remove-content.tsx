'use client';

import { useState, useTransition } from 'react';
import type { ReportReason } from '@repo/shared';
import type { ActionResult } from '@/controllers/moderation.actions';
import { REPORT_REASON_LABELS, REPORT_REASONS } from '@/lib/report-labels';
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
import { NativeSelect, NativeSelectOption } from '@/components/ui/native-select';

// Suppression d'un contenu par modération (ADR-038), confirmée dans une alerte avec le motif annoncé à son auteur.
// `action` est une Server Action liée à sa cible, qui reçoit le motif. `defaultReason` : le motif le plus signalé,
// depuis la page d'un signalement ; sans lui, le motif doit être choisi. `confirmLabel` / `pendingLabel` : textes du
// bouton de confirmation (« Arrêter » pour un live, ADR-053).
export function RemoveContent({
  label,
  title,
  description,
  action,
  defaultReason,
  size = 'sm',
  confirmLabel = 'Supprimer',
  pendingLabel = 'Suppression…',
}: {
  label: string;
  title: string;
  description: string;
  action: (reason: ReportReason) => Promise<ActionResult>;
  defaultReason?: ReportReason;
  size?: 'sm' | 'default';
  confirmLabel?: string;
  pendingLabel?: string;
}) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState<ReportReason | ''>(defaultReason ?? '');
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function confirm(event: React.MouseEvent) {
    event.preventDefault();
    if (!reason) return;
    startTransition(async () => {
      const result = await action(reason);
      setError(result?.error ?? null);
      if (!result?.error) setOpen(false);
    });
  }

  return (
    <AlertDialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        setError(null);
        if (next) setReason(defaultReason ?? '');
      }}
    >
      <AlertDialogTrigger asChild>
        <Button variant="destructive" size={size}>
          {label}
        </Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{title}</AlertDialogTitle>
          <AlertDialogDescription>{description}</AlertDialogDescription>
        </AlertDialogHeader>
        <div className="flex flex-col gap-2">
          <Label htmlFor="removal-reason">Motif, annoncé à l’auteur</Label>
          <NativeSelect
            id="removal-reason"
            className="w-full"
            value={reason}
            onChange={(event) => setReason(event.target.value as ReportReason)}
            disabled={pending}
          >
            <NativeSelectOption value="" disabled>
              Choisir un motif
            </NativeSelectOption>
            {REPORT_REASONS.map((value) => (
              <NativeSelectOption key={value} value={value}>
                {REPORT_REASON_LABELS[value]}
              </NativeSelectOption>
            ))}
          </NativeSelect>
        </div>
        {error && <p className="text-sm text-destructive">{error}</p>}
        <AlertDialogFooter>
          <AlertDialogCancel disabled={pending}>Annuler</AlertDialogCancel>
          <AlertDialogAction variant="destructive" onClick={confirm} disabled={pending || !reason}>
            {pending ? pendingLabel : confirmLabel}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
