import type { Comment } from '../../interactions/domain/interaction';
import type { OpenReportTarget, Report, ReportTarget } from '../../reports/domain/report';
import type { User } from '../../users/domain/user';
import type { VideoDetails, VideoStatus } from '../../videos/domain/video';
import type { WalletLedgerEntry, WalletStats } from '../../wallet/domain/wallet';

// Backoffice (ADR-004). Le module n'a pas de données propres : il assemble ce que les autres modules
// exposent par leurs services (ADR-003), pour les écrans d'administration.

export const DEFAULT_ADMIN_PAGE_SIZE = 20;
export const MAX_ADMIN_PAGE_SIZE = 100;
// Période des nouveautés du tableau de bord.
export const RECENT_PERIOD_DAYS = 7;

// Un compte, son rôle, son nombre de vidéos (tous statuts), son solde de jetons et sa suspension en cours.
export interface AdminAccount {
  user: User;
  isAdmin: boolean;
  videosCount: number;
  tokenBalance: number;
  suspension: AccountModeration | null;
}

// Suspension en cours (ADR-037), avec l'administrateur auteur (null s'il a supprimé son compte depuis).
export interface AccountModeration {
  suspendedAt: Date;
  reason: string;
  suspendedBy: User | null;
}

// Une ligne du journal des jetons et le compte crédité (null : supprimé depuis, ou client inconnu).
export interface LedgerLine {
  entry: WalletLedgerEntry;
  user: User | null;
}

export interface ModeratedVideo {
  video: VideoDetails;
  author: User;
}

export interface ModeratedComment {
  comment: Comment;
  author: User;
  video: VideoDetails;
}

// Page d'une liste triée de la plus récente à la plus ancienne. Le curseur est l'identifiant du dernier
// élément lu (UUID v7, ordonné dans le temps), même quand cet élément a été sauté faute d'auteur.
export interface Page<T> {
  items: T[];
  nextCursor: string | null;
}

export interface RecentCount {
  total: number;
  last7Days: number;
}

// Une cible de la file des signalements (ADR-038), avec ce qu'il faut pour l'afficher.
export interface ModeratedReportTarget {
  target: ReportTarget;
  targetUser: User;
  // Faux si le contenu a disparu depuis.
  available: boolean;
  thumbnailUrl: string | null;
  // Commentaire : vidéo commentée.
  videoId: string | null;
  // Nul si aucun signalement n'est plus ouvert (page d'une cible déjà traitée).
  open: OpenReportTarget | null;
  // Extrait du signalement le plus récent.
  excerpt: string | null;
  latestAt: Date;
}

export interface ModeratedReport {
  report: Report;
  reporter: User | null;
  resolvedBy: User | null;
}

export interface ReportTargetDetail {
  target: ModeratedReportTarget;
  reports: ModeratedReport[];
}

export interface PlatformStats {
  reports: { openTargets: number };
  users: RecentCount & { suspended: number };
  videos: RecentCount & Record<VideoStatus, number>;
  comments: RecentCount;
  // `purchasedSince` : sur les 7 derniers jours.
  tokens: WalletStats;
}
