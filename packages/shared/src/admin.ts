import type { UserSummaryDto } from './users.js';
import type { VideoStatus } from './videos.js';

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
  createdAt: string;
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

export interface AdminStatsDto {
  users: AdminCountDto;
  videos: AdminVideoCountsDto;
  comments: AdminCountDto;
}
