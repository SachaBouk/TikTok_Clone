import type { UserSummaryDto } from './users.js';

// Cycle de vie d'une vidéo (ADR-008).
export type VideoStatus = 'uploading' | 'processing' | 'ready' | 'failed';

// Visibilité (ADR-061) : publique, ou privée (« Toi uniquement »), visible de son seul auteur.
export type VideoVisibility = 'public' | 'private';

// Lieu de la publication (ADR-065) : nom et adresse affichée, jamais de coordonnées.
export interface VideoLocationDto {
  name: string;
  address?: string;
}

export interface VideoDto {
  id: string;
  userId: string;
  description: string | null;
  status: VideoStatus;
  visibility: VideoVisibility;
  // Commentaires autorisés (ADR-062).
  commentsEnabled: boolean;
  // « Autoriser l'utilisation de mon son » (ADR-064).
  soundShared: boolean;
  // Étiquette « Contenu généré par l'IA » (ADR-065).
  aiGenerated: boolean;
  // Absent sans lieu (ADR-065).
  location?: VideoLocationDto;
  // Renseignés quand la vidéo est `ready` (ADR-008).
  hlsUrl: string | null;
  thumbnailUrl: string | null;
  createdAt: string;
}

// URL signée pour envoyer une partie directement au stockage (PUT, ADR-007).
export interface UploadPartUrlDto {
  partNumber: number;
  url: string;
}

export interface VideoUploadDto {
  video: VideoDto;
  // Taille de chaque partie en octets (la dernière peut être plus petite).
  partSize: number;
  parts: UploadPartUrlDto[];
  // Expiration des URLs signées.
  expiresAt: string;
  // Couverture choisie (ADR-065) : URL signée pour un seul PUT du JPEG, si `cover` a été demandé.
  coverUrl?: string;
}

// Vidéos de l'auteur pas encore publiées (`processing`) ou en échec (`failed`), à afficher en tête de sa grille.
export interface PendingVideosDto {
  // De la plus récente à la plus ancienne (50 au plus).
  items: VideoDto[];
}

// Son repris d'une vidéo publiée (ADR-064) : « Son original - @pseudo ».
export interface SoundDto {
  id: string;
  // Vidéo d'où vient le son.
  videoId: string;
  author: UserSummaryDto;
  // Fichier AAC du son (CDN, bucket HLS en local).
  audioUrl: string;
  // Durée, en secondes.
  duration: number;
  // Miniature de la vidéo d'origine.
  coverUrl: string;
  // Vidéos publiques publiées qui l'utilisent.
  usesCount: number;
  createdAt: string;
  // Absent en invité.
  viewer?: SoundViewerStateDto;
}

export interface SoundViewerStateDto {
  favorited: boolean;
}

export interface SoundPageDto {
  items: SoundDto[];
  nextCursor: string | null;
}

export interface SoundListDto {
  items: SoundDto[];
}
