import type { ReportReason, ReportResolution, ReportTargetType } from '@repo/shared';

// Libellés des signalements (ADR-038), comme dans l'app.
export const REPORT_REASON_LABELS: Record<ReportReason, string> = {
  spam: 'Spam',
  harassment: 'Harcèlement',
  hate: 'Contenu haineux',
  violence: 'Violence',
  sexual: 'Nudité ou contenu sexuel',
  impersonation: 'Usurpation d’identité',
  other: 'Autre',
};

export const REPORT_TARGET_LABELS: Record<ReportTargetType, string> = {
  video: 'Vidéo',
  comment: 'Commentaire',
  account: 'Compte',
};

export const REPORT_RESOLUTION_LABELS: Record<ReportResolution, string> = {
  contentRemoved: 'Contenu supprimé',
  accountSuspended: 'Compte suspendu',
  dismissed: 'Sans suite',
};

export const REPORT_TARGET_TYPES: ReportTargetType[] = ['video', 'comment', 'account'];
