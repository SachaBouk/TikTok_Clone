import type { UserSummaryDto } from './users.js';

// Signalements (ADR-038) : une vidéo, un commentaire ou un compte, avec un motif de la liste et une précision.

export type ReportTargetType = 'video' | 'comment' | 'account' | 'message';

export type ReportReason = 'spam' | 'harassment' | 'hate' | 'violence' | 'sexual' | 'impersonation' | 'other';

// Décision d'un administrateur, qui clôt tous les signalements ouverts d'une cible ; ou clôture automatique quand la
// cible disparaît sans décision (contenu supprimé par son auteur, compte supprimé).
export type ReportResolution = 'contentRemoved' | 'accountSuspended' | 'dismissed' | 'contentDeleted' | 'accountDeleted';

export interface CreateReportDto {
  targetType: ReportTargetType;
  targetId: string;
  reason: ReportReason;
  // 500 caractères au plus.
  details?: string;
}

// ─── Backoffice ──────────────────────────────────────────────────────────────

export interface AdminReportReasonCountDto {
  reason: ReportReason;
  count: number;
}

// Une cible signalée, telle que la file de modération l'affiche.
export interface AdminReportTargetDto {
  targetType: ReportTargetType;
  targetId: string;
  // Compte visé : auteur du contenu, ou le compte lui-même ; absent s'il a été supprimé depuis.
  targetUser?: UserSummaryDto;
  // Pseudo du compte visé au moment du signalement (reste après sa suppression).
  targetUsername: string;
  // Faux si le contenu a disparu depuis (supprimé par son auteur, vidéo dépubliée).
  available: boolean;
  // Vidéo : miniature (absente si elle n'est plus disponible).
  thumbnailUrl?: string;
  // Commentaire : vidéo commentée.
  videoId?: string;
  // Texte signalé, copié au moment du signalement le plus récent (commentaire, description de la vidéo).
  excerpt?: string;
  // Signalements ouverts, et leur répartition par motif (du plus fréquent au moins fréquent).
  openCount: number;
  reasons: AdminReportReasonCountDto[];
  latestAt: string;
}

export interface AdminReportTargetPageDto {
  items: AdminReportTargetDto[];
  nextCursor: string | null;
}

export interface AdminReportDto {
  id: string;
  // Absent si la personne a supprimé son compte depuis.
  reporter?: UserSummaryDto;
  reason: ReportReason;
  details: string | null;
  excerpt: string | null;
  createdAt: string;
  // Absents tant que le signalement est ouvert.
  resolution?: ReportResolution;
  resolvedAt?: string;
  resolvedBy?: UserSummaryDto;
}

// Une cible et ses signalements (ouverts et clos), du plus récent au plus ancien, 100 au plus.
export interface AdminReportTargetDetailDto {
  target: AdminReportTargetDto;
  reports: AdminReportDto[];
}

// ─── Journal de modération ───────────────────────────────────────────────────

export type ModerationActionType =
  'videoRemoved' | 'commentRemoved' | 'messageRemoved' | 'accountSuspended' | 'suspensionLifted' | 'reportsDismissed';

// Une action d'un administrateur ; pseudos et texte copiés (le journal survit aux suppressions).
export interface AdminModerationActionDto {
  id: string;
  action: ModerationActionType;
  // Absent si l'administrateur a supprimé son compte depuis.
  admin?: UserSummaryDto;
  adminUsername: string;
  targetType: ReportTargetType;
  targetId: string;
  // Absent si le compte visé a été supprimé depuis.
  targetUser?: UserSummaryDto;
  targetUsername: string | null;
  // Contenu retiré : motif de la liste.
  reason?: ReportReason;
  // Suspension : motif saisi.
  note: string | null;
  excerpt: string | null;
  reportsClosed: number;
  createdAt: string;
}

export interface AdminModerationActionPageDto {
  items: AdminModerationActionDto[];
  nextCursor: string | null;
}
