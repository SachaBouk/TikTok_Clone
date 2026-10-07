import type { UserSummaryDto } from './users.js';
import type { VideoStatus } from './videos.js';
import type { GiftDto, GiftVideoDto, WalletTransactionKind } from './wallet.js';

// Backoffice (ADR-004) : routes `/admin`, réservées aux comptes au rôle `admin`.

// Rôle d'un compte, attribué hors de l'API (`pnpm admin:grant`).
export type UserRole = 'user' | 'admin';

// Un compte vu par le backoffice.
export interface AdminUserDto {
  id: string;
  username: string;
  displayName: string;
  avatarUrl: string | null;
  bio: string | null;
  role: UserRole;
  followersCount: number;
  followingCount: number;
  // Vidéos du compte, tous statuts confondus.
  videosCount: number;
  // Solde de jetons (ADR-009).
  tokenBalance: number;
  // Jetons reçus en cadeaux (ADR-050), non dépensables.
  tokenEarned: number;
  createdAt: string;
  // Suspension en cours (ADR-037) ; absente si le compte n'est pas suspendu.
  suspension?: AdminSuspensionDto;
}

// Suspension d'un compte par un administrateur (ADR-037), jusqu'à sa levée.
export interface AdminSuspensionDto {
  suspendedAt: string;
  // Motif interne : la personne suspendue voit un message générique.
  reason: string;
  // Administrateur auteur ; absent s'il a supprimé son compte depuis.
  suspendedBy?: UserSummaryDto;
}

export interface AdminSuspendUserDto {
  reason: string;
}

export interface AdminUserPageDto {
  // Du compte le plus récent au plus ancien.
  items: AdminUserDto[];
  // À renvoyer tel quel pour la page suivante ; null s'il n'y en a plus.
  nextCursor: string | null;
}

// Une vidéo vue par le backoffice, quel que soit son statut.
export interface AdminVideoDto {
  id: string;
  author: UserSummaryDto;
  description: string | null;
  status: VideoStatus;
  hlsUrl: string | null;
  thumbnailUrl: string | null;
  viewsCount: number;
  likesCount: number;
  commentsCount: number;
  favoritesCount: number;
  repostsCount: number;
  sharesCount: number;
  createdAt: string;
}

export interface AdminVideoPageDto {
  // De la vidéo la plus récente à la plus ancienne.
  items: AdminVideoDto[];
  nextCursor: string | null;
}

// Vidéo commentée, pour la liste des commentaires.
export interface AdminCommentVideoDto {
  id: string;
  status: VideoStatus;
  thumbnailUrl: string | null;
}

export interface AdminCommentDto {
  id: string;
  content: string;
  createdAt: string;
  author: UserSummaryDto;
  video: AdminCommentVideoDto;
}

export interface AdminCommentPageDto {
  // Du commentaire le plus récent au plus ancien.
  items: AdminCommentDto[];
  nextCursor: string | null;
}

// Tableau de bord : un total, et ce qui a été créé sur les 7 derniers jours.
export interface AdminCountDto {
  total: number;
  last7Days: number;
}

export interface AdminVideoCountsDto extends AdminCountDto {
  uploading: number;
  processing: number;
  ready: number;
  failed: number;
}

// Jetons annoncés par RevenueCat pour un environnement (montants positifs, sauf les ajustements, nets).
export interface AdminTokenTotalsDto {
  // Jetons vendus, clients inconnus compris (le store a encaissé).
  purchased: number;
  refunded: number;
  adjusted: number;
}

export interface AdminTokenStatsDto {
  production: AdminTokenTotalsDto;
  // Achats de test (Xcode, TestFlight, Test Store), jamais payés.
  sandbox: AdminTokenTotalsDto;
  // Jetons vendus en production sur les 7 derniers jours.
  purchasedLast7Days: number;
  // Somme des soldes des comptes.
  inCirculation: number;
  // Mouvements d'un client inconnu de l'API, à rapprocher à la main.
  unmatched: number;
  // Cadeaux (ADR-050) : jetons dépensés (total et 7 derniers jours), gains des comptes existants.
  giftsSpent: number;
  giftsSpentLast7Days: number;
  earned: number;
}

export interface AdminUserCountsDto extends AdminCountDto {
  // Comptes suspendus en ce moment (ADR-037).
  suspended: number;
}

// Signalements (ADR-038).
export interface AdminReportCountsDto {
  // Cibles avec au moins un signalement ouvert (taille de la file de modération).
  openTargets: number;
}

export interface AdminStatsDto {
  reports: AdminReportCountsDto;
  users: AdminUserCountsDto;
  videos: AdminVideoCountsDto;
  comments: AdminCountDto;
  tokens: AdminTokenStatsDto;
}

// Une ligne du journal des jetons (ADR-021), avec ce qui sert au rapprochement avec RevenueCat et le store.
export interface AdminWalletTransactionDto {
  id: string;
  // Compte crédité ; absent pour un compte supprimé depuis ou un client inconnu (`unmatched`).
  user?: UserSummaryDto;
  kind: WalletTransactionKind;
  // Mouvement annoncé par RevenueCat.
  amount: number;
  // Mouvement réellement appliqué au solde (plancher à 0 ; 0 pour un client inconnu).
  appliedAmount: number;
  balanceAfter: number | null;
  // Client inconnu de l'API au moment du webhook : aucun solde touché.
  unmatched: boolean;
  revenuecatEventId: string;
  // Identifiant du client chez RevenueCat.
  appUserId: string;
  productId: string | null;
  storeTransactionId: string | null;
  store: string | null;
  // PRODUCTION ou SANDBOX.
  environment: string;
  occurredAt: string;
}

export interface AdminWalletTransactionPageDto {
  // Du mouvement le plus récent au plus ancien.
  items: AdminWalletTransactionDto[];
  nextCursor: string | null;
}

// Journal des cadeaux (ADR-050) : un cadeau envoyé, avec ses deux comptes (absents : supprimés depuis) et sa vidéo.
export interface AdminGiftDto {
  id: string;
  gift: GiftDto;
  // Prix payé, en jetons.
  amount: number;
  // Solde de l'expéditeur après le débit.
  senderBalanceAfter: number;
  sender?: UserSummaryDto;
  recipient?: UserSummaryDto;
  // Absente si elle n'est plus publiée ; `videoId` nul si elle a été supprimée.
  video?: GiftVideoDto;
  videoId: string | null;
  createdAt: string;
}

export interface AdminGiftPageDto {
  // Du plus récent au plus ancien.
  items: AdminGiftDto[];
  nextCursor: string | null;
}
