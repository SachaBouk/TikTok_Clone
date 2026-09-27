// Cycle de vie (ADR-008) : uploading → processing → ready / failed.
export type VideoStatus = 'uploading' | 'processing' | 'ready' | 'failed';

export interface Video {
  id: string;
  userId: string;
  description: string | null;
  // Clé de l'objet brut dans le bucket des uploads.
  rawKey: string;
  // Upload multipart en cours ; nul une fois l'upload terminé.
  uploadId: string | null;
  // Taille déclarée du fichier brut, en octets.
  rawSize: number;
  status: VideoStatus;
  hlsUrl: string | null;
  thumbnailUrl: string | null;
  createdAt: Date;
}

// Vidéo publiée (`ready`), telle que diffusée dans le feed : lecture HLS et compteurs dénormalisés (ADR-006).
export interface PublishedVideo {
  id: string;
  userId: string;
  description: string | null;
  hlsUrl: string;
  thumbnailUrl: string;
  viewsCount: number;
  likesCount: number;
  commentsCount: number;
  favoritesCount: number;
  sharesCount: number;
  repostsCount: number;
  createdAt: Date;
}

// Vidéo vue par le backoffice (ADR-004) : quel que soit son statut, avec ses compteurs.
export interface VideoDetails {
  id: string;
  userId: string;
  description: string | null;
  status: VideoStatus;
  hlsUrl: string | null;
  thumbnailUrl: string | null;
  viewsCount: number;
  likesCount: number;
  commentsCount: number;
  favoritesCount: number;
  sharesCount: number;
  repostsCount: number;
  createdAt: Date;
}

// Filtres de la liste des vidéos du backoffice.
export interface VideoFilter {
  status?: VideoStatus;
  userId?: string;
}

// Vidéos non publiées (en traitement ou en échec) montrées à leur auteur : les plus récentes seulement.
// Il n'y a pas encore de suppression de vidéo : les échecs s'accumulent.
export const MAX_UNPUBLISHED_VIDEOS = 50;

// Position dans une liste de vidéos triée de la plus récente à la plus ancienne (date, puis identifiant).
export interface VideoPosition {
  createdAt: Date;
  id: string;
}

// Résultat du transcodage renvoyé par le worker (ADR-008, ADR-012).
export type TranscodeOutcome = { status: 'ready'; hlsUrl: string; thumbnailUrl: string } | { status: 'failed' };

export interface NewVideo {
  userId: string;
  description: string | null;
  rawKey: string;
  uploadId: string;
  rawSize: number;
}
