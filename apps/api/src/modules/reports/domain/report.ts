import type { RateLimitRule } from '../../../rate-limit/rate-limiter';

// Signalements (ADR-038) : une personne signale une vidéo, un commentaire ou un compte, avec un motif de la liste
// et une précision facultative. Rien n'est masqué avant la décision d'un administrateur.

export type ReportTargetType = 'video' | 'comment' | 'account';
export type ReportReason = 'spam' | 'harassment' | 'hate' | 'violence' | 'sexual' | 'impersonation' | 'other';
// Décision qui clôt les signalements ouverts d'une cible.
export type ReportResolution = 'contentRemoved' | 'accountSuspended' | 'dismissed';

export const REPORT_TARGET_TYPES: ReportTargetType[] = ['video', 'comment', 'account'];
export const REPORT_REASONS: ReportReason[] = ['spam', 'harassment', 'hate', 'violence', 'sexual', 'impersonation', 'other'];

export const MAX_REPORT_DETAILS_LENGTH = 500;
// Anti-abus : par personne, fenêtres fixes du limiteur partagé (ADR-030). Un signalement en double ne compte pas.
export const REPORT_RATE_LIMITS: RateLimitRule[] = [
  { limit: 10, windowSeconds: 3600 },
  { limit: 50, windowSeconds: 86_400 },
];

export const DEFAULT_REPORT_TARGETS_PAGE_SIZE = 20;
export const MAX_REPORT_TARGETS_PAGE_SIZE = 100;
// Signalements montrés sur la page d'une cible.
export const MAX_REPORTS_PER_TARGET = 100;

export interface ReportTarget {
  type: ReportTargetType;
  id: string;
}

export interface NewReport {
  reporterId: string;
  target: ReportTarget;
  targetUserId: string;
  reason: ReportReason;
  details: string | null;
  excerpt: string | null;
}

export interface Report {
  id: string;
  // Nul si la personne a supprimé son compte depuis.
  reporterId: string | null;
  target: ReportTarget;
  targetUserId: string;
  reason: ReportReason;
  details: string | null;
  excerpt: string | null;
  createdAt: Date;
  resolution: ReportResolution | null;
  resolvedAt: Date | null;
  resolvedBy: string | null;
}

// Une cible de la file de modération : ses signalements ouverts, groupés.
export interface OpenReportTarget {
  target: ReportTarget;
  targetUserId: string;
  openCount: number;
  // Du plus fréquent au moins fréquent.
  reasons: { reason: ReportReason; count: number }[];
  // Signalement ouvert le plus récent : tri et curseur (UUID v7, ordonné dans le temps).
  latestId: string;
  latestAt: Date;
  // Extrait du signalement le plus récent.
  excerpt: string | null;
}
