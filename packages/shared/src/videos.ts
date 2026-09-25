// Cycle de vie d'une vidéo (ADR-008).
export type VideoStatus = 'uploading' | 'processing' | 'ready' | 'failed';

export interface VideoDto {
  id: string;
  userId: string;
  description: string | null;
  status: VideoStatus;
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
}

// Vidéos de l'auteur pas encore publiées (`processing`) ou en échec (`failed`), à afficher en tête de sa grille.
export interface PendingVideosDto {
  // De la plus récente à la plus ancienne (50 au plus).
  items: VideoDto[];
}
