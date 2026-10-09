import type { RateLimitRule } from '../../../rate-limit/rate-limiter';

// Signalements (ADR-038) : une personne signale une vidéo, un commentaire, un compte, un message reçu ou une story (ADR-051), avec un motif
// de la liste et une précision facultative. Rien n'est masqué avant la décision d'un administrateur.

export type ReportTargetType = 'video' | 'comment' | 'account' | 'message' | 'story' | 'live';
export type ReportReason = 'spam' | 'harassment' | 'hate' | 'violence' | 'sexual' | 'impersonation' | 'other';
// Décision d'un administrateur, qui clôt les signalements ouverts d'une cible ; ou clôture automatique par la base
// (triggers) quand la cible disparaît sans décision : contenu supprimé par son auteur, compte supprimé.
export type ReportResolution = 'contentRemoved' | 'accountSuspended' | 'dismissed' | 'contentDeleted' | 'accountDeleted';
// Décision annoncée à la personne qui a signalé.
export type ModerationOutcome = 'contentRemoved' | 'accountSuspended' | 'dismissed';

export const REPORT_TARGET_TYPES: ReportTargetType[] = ['video', 'comment', 'account', 'message', 'story', 'live'];
export const REPORT_RESOLUTIONS: ReportResolution[] = ['contentRemoved', 'accountSuspended', 'dismissed', 'contentDeleted', 'accountDeleted'];
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
  targetUsername: string;
  reason: ReportReason;
  details: string | null;
  excerpt: string | null;
}

export interface Report {
  id: string;
  // Nul si la personne a supprimé son compte depuis.
  reporterId: string | null;
  target: ReportTarget;
  // Nul si le compte visé a été supprimé depuis ; son pseudo reste.
  targetUserId: string | null;
  targetUsername: string;
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
  // Une cible ouverte a toujours son compte : sa suppression clôt ses signalements (trigger).
  targetUserId: string;
  targetUsername: string;
  openCount: number;
  // Du plus fréquent au moins fréquent.
  reasons: { reason: ReportReason; count: number }[];
  // Signalement ouvert le plus récent : tri et curseur (UUID v7, ordonné dans le temps).
  latestId: string;
  latestAt: Date;
  // Extrait du signalement le plus récent.
  excerpt: string | null;
}

// Signalement clos par une décision : de quoi prévenir la personne qui l'a envoyé et journaliser.
export interface ResolvedReport {
  reporterId: string | null;
  target: ReportTarget;
  targetUserId: string | null;
  targetUsername: string;
  excerpt: string | null;
}

// ─── Journal de modération ───────────────────────────────────────────────────

export type ModerationActionType =
  'videoRemoved' | 'commentRemoved' | 'messageRemoved' | 'storyRemoved' | 'liveEnded' | 'accountSuspended' | 'suspensionLifted' | 'reportsDismissed';
export const MODERATION_ACTION_TYPES: ModerationActionType[] = [
  'videoRemoved',
  'commentRemoved',
  'messageRemoved',
  'storyRemoved',
  'liveEnded',
  'accountSuspended',
  'suspensionLifted',
  'reportsDismissed',
];

// Une action d'un administrateur. Pseudos et texte copiés : le journal survit à la suppression des comptes et contenus.
export interface NewModerationAction {
  adminId: string;
  adminUsername: string;
  action: ModerationActionType;
  target: ReportTarget;
  targetUserId: string | null;
  targetUsername: string | null;
  // Motif de la liste (contenu retiré).
  reason: ReportReason | null;
  // Texte libre (motif de la suspension).
  note: string | null;
  excerpt: string | null;
  reportsClosed: number;
}

export interface ModerationAction extends Omit<NewModerationAction, 'adminId'> {
  id: string;
  // Nul si l'administrateur a supprimé son compte depuis.
  adminId: string | null;
  createdAt: Date;
}

export const DEFAULT_MODERATION_ACTIONS_PAGE_SIZE = 25;
export const MAX_MODERATION_ACTIONS_PAGE_SIZE = 100;
