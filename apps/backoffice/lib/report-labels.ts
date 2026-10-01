import type { ModerationActionType, ReportReason, ReportResolution, ReportTargetType } from '@repo/shared';

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
  message: 'Message',
};

export const REPORT_RESOLUTION_LABELS: Record<ReportResolution, string> = {
  contentRemoved: 'Contenu supprimé',
  accountSuspended: 'Compte suspendu',
  dismissed: 'Sans suite',
  // Closes par la base, sans décision : contenu supprimé par son auteur, compte supprimé.
  contentDeleted: 'Supprimé par son auteur',
  accountDeleted: 'Compte supprimé',
};

export const REPORT_TARGET_TYPES: ReportTargetType[] = ['video', 'comment', 'account', 'message'];
export const REPORT_REASONS = Object.keys(REPORT_REASON_LABELS) as ReportReason[];

// Journal de modération.
export const MODERATION_ACTION_LABELS: Record<ModerationActionType, string> = {
  videoRemoved: 'Vidéo supprimée',
  commentRemoved: 'Commentaire supprimé',
  messageRemoved: 'Message supprimé',
  accountSuspended: 'Compte suspendu',
  suspensionLifted: 'Suspension levée',
  reportsDismissed: 'Signalements classés sans suite',
};
