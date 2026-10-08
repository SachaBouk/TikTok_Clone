import type { UploadPartUrlDto } from './videos.js';
import type { UserSummaryDto } from './users.js';

// Stories (ADR-051) : vidéo (60 s au plus) ou photo, visibles 24 h après leur publication, puis supprimées.

export type StoryMediaType = 'video' | 'photo';
// Une photo passe directement de `uploading` à `ready` ; une vidéo passe par le transcodage (`processing`).
export type StoryStatus = 'uploading' | 'processing' | 'ready' | 'failed';

export interface StoryDto {
  id: string;
  userId: string;
  mediaType: StoryMediaType;
  status: StoryStatus;
  // Manifeste HLS (vidéo) ou photo JPEG, quand la story est `ready`.
  mediaUrl: string | null;
  thumbnailUrl: string | null;
  createdAt: string;
  // Publication (`ready`) et fin de visibilité, 24 h plus tard ; nulles avant la publication.
  publishedAt: string | null;
  expiresAt: string | null;
}

export interface StoryUploadDto {
  story: StoryDto;
  // Taille de chaque partie en octets (la dernière peut être plus petite).
  partSize: number;
  parts: UploadPartUrlDto[];
  // Expiration des URLs signées.
  expiresAt: string;
}

// État propre au compte connecté qui regarde la story d'un autre.
export interface StoryViewerStateDto {
  viewed: boolean;
  liked: boolean;
}

// Chiffres d'une story, pour son auteur seulement.
export interface StoryStatsDto {
  viewersCount: number;
  likesCount: number;
}

export interface StoryItemDto extends StoryDto {
  // Absent en mode invité et pour l'auteur.
  viewer?: StoryViewerStateDto;
  // Pour l'auteur seulement.
  stats?: StoryStatsDto;
}

// Stories actives d'un compte, de la plus ancienne à la plus récente (ordre de lecture).
export interface UserStoriesDto {
  user: UserSummaryDto;
  items: StoryItemDto[];
}

// Un compte de la rangée de stories (compte connecté : soi, puis ses abonnements).
export interface StoryTrayItemDto {
  user: UserSummaryDto;
  storiesCount: number;
  latestAt: string;
  // Au moins une story pas encore vue par le compte connecté (toujours faux pour soi).
  hasUnseen: boolean;
}

export interface StoryTrayDto {
  items: StoryTrayItemDto[];
}

export interface StoryViewerDto {
  user: UserSummaryDto;
  viewedAt: string;
  liked: boolean;
}

export interface StoryViewersPageDto {
  items: StoryViewerDto[];
  nextCursor: string | null;
  viewersCount: number;
  likesCount: number;
}

// Anneau autour de l'avatar d'un auteur dans le feed : il a une story visible.
export interface AuthorStoryDto {
  hasUnseen: boolean;
}

// Story à laquelle répond un message (ADR-051). Une story expirée ou supprimée depuis reste signalée, indisponible.
export interface MessageStoryDto {
  id: string;
  available: boolean;
  // Absents si la story n'est plus disponible.
  mediaType?: StoryMediaType;
  thumbnailUrl: string | null;
}
