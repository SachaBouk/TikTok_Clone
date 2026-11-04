import type { RateLimitRule } from '../../../rate-limit/rate-limiter';
import { readJpegDimensions, type ImageDimensions } from '../../users/domain/image-dimensions';
import { MAX_VIDEO_SIZE_BYTES, SUPPORTED_VIDEO_TYPES } from '../../videos/domain/upload-rules';
import type { VideoProvider } from '../../videos/domain/video';

// Stories (ADR-051) : vidéo (60 s au plus) ou photo, visibles 24 h après leur publication, puis supprimées avec leurs
// vues et leurs fichiers. Publiques comme les vidéos ; masquées pour un compte suspendu ou bloqué (ADR-029, ADR-037).

export type StoryMediaType = 'video' | 'photo';
// Une photo passe directement de `uploading` à `ready` ; une vidéo passe par le transcodage (ADR-008).
export type StoryStatus = 'uploading' | 'processing' | 'ready' | 'failed';

export interface Story {
  id: string;
  userId: string;
  mediaType: StoryMediaType;
  status: StoryStatus;
  // Vidéo : clé du brut dans le bucket des uploads. Photo : clé de la photo dans le bucket public des médias.
  rawKey: string;
  // Upload multipart en cours ; nul une fois l'upload terminé (toujours nul pour une story Mux).
  uploadId: string | null;
  rawSize: number;
  // Story vidéo chez Mux (ADR-074) : envoi direct, asset, identifiant de lecture (public). Jamais exposés.
  provider: VideoProvider;
  muxUploadId: string | null;
  muxAssetId: string | null;
  muxPlaybackId: string | null;
  mediaUrl: string | null;
  thumbnailUrl: string | null;
  createdAt: Date;
  publishedAt: Date | null;
  expiresAt: Date | null;
}

// Story publiée et pas encore expirée.
export interface ActiveStory extends Story {
  status: 'ready';
  mediaUrl: string;
  thumbnailUrl: string;
  publishedAt: Date;
  expiresAt: Date;
}

export interface NewStory {
  id: string;
  userId: string;
  mediaType: StoryMediaType;
  rawKey: string;
  // Upload multipart S3 ; nul pour une story vidéo envoyée chez Mux (ADR-074).
  uploadId: string | null;
  rawSize: number;
  provider?: VideoProvider;
  muxUploadId?: string | null;
}

// Vue d'une story par un compte (un like vaut vue).
export interface StoryView {
  userId: string;
  viewedAt: Date;
  liked: boolean;
}

// Chiffres d'une story, pour son auteur.
export interface StoryStats {
  viewersCount: number;
  likesCount: number;
}

// Comptes ayant des stories actives (rangée), avec ce qu'en a vu le lecteur.
export interface StoryAuthorSummary {
  userId: string;
  storiesCount: number;
  latestAt: Date;
  // Stories actives vues par le lecteur (toujours 0 pour un invité).
  viewedCount: number;
}

// Position dans la liste des personnes qui ont vu une story (date de la vue, puis compte).
export interface StoryViewPosition {
  viewedAt: Date;
  userId: string;
}

// Fichiers d'une story à supprimer : brut (vidéo) ou photo, upload multipart en cours, et tout `<storyId>/` du bucket
// des médias (HLS et miniature).
export interface StoryFiles {
  storyId: string;
  mediaType: StoryMediaType;
  rawKey: string | null;
  uploadId: string | null;
  // Story Mux (ADR-074) : envoi direct à annuler, asset à supprimer.
  muxUploadId?: string | null;
  muxAssetId?: string | null;
}

// Résultat du transcodage d'une story vidéo (ADR-012).
export type StoryTranscodeOutcome = { status: 'ready'; mediaUrl: string; thumbnailUrl: string } | { status: 'failed' };

// ─── Règles ──────────────────────────────────────────────────────────────────

// Visible 24 h après la publication (passage en `ready`).
export const STORY_LIFETIME_MS = 24 * 60 * 60 * 1000;
// Stories actives par compte (envoi en cours, en traitement, ou publiée et pas expirée) : au-delà, 409.
export const MAX_ACTIVE_STORIES = 30;

// Formats acceptés : ceux des vidéos (galerie iOS), et une photo JPEG préparée par l'app.
export const SUPPORTED_STORY_TYPES = {
  ...SUPPORTED_VIDEO_TYPES,
  'image/jpeg': 'jpg',
} as const;
export type SupportedStoryType = keyof typeof SUPPORTED_STORY_TYPES;
export const MAX_STORY_VIDEO_SIZE_BYTES = MAX_VIDEO_SIZE_BYTES;
export const MAX_STORY_PHOTO_SIZE_BYTES = 5 * 1024 * 1024;

// Photo : 9:16 exact, de 360×640 à 1080×1920 px (l'app produit 1080×1920). En-tête lu par l'API, comme l'ADR-046.
export const STORY_PHOTO_MIN_WIDTH = 360;
export const STORY_PHOTO_MAX_WIDTH = 1080;
export const STORY_PHOTO_HEADER_LENGTH = 64 * 1024;

// Limites de débit (ADR-039) : une story vidéo compte dans la limite des envois de vidéos (même compteur) ; photos à part.
export const PHOTO_STORY_RATE_LIMITS: RateLimitRule[] = [
  { limit: 20, windowSeconds: 3600 },
  { limit: 50, windowSeconds: 24 * 3600 },
];
export const STORY_LIKE_RATE_LIMITS: RateLimitRule[] = [
  { limit: 60, windowSeconds: 60 },
  { limit: 600, windowSeconds: 3600 },
];
// Au-delà, les vues sont ignorées sans erreur, comme celles des vidéos.
export const STORY_VIEW_RATE_LIMITS: RateLimitRule[] = [{ limit: 600, windowSeconds: 3600 }];

// Maintenance : une story non publiée plus de 24 h après sa création (envoi abandonné, échec, traitement bloqué) est
// supprimée ; un transcodage sans nouvelles depuis 1 h est relancé (sans effet si le job existe encore).
export const UNPUBLISHED_STORY_TTL_MS = 24 * 60 * 60 * 1000;
export const STUCK_STORY_TRANSCODE_AFTER_MS = 60 * 60 * 1000;
// Story Mux (ADR-074) en traitement depuis 15 min : son état est relu chez Mux (webhook perdu).
export const STUCK_HOSTED_STORY_AFTER_MS = 15 * 60 * 1000;
// Durée maximale d'une story vidéo, à une seconde près, comme le worker : vérifiée par l'API pour une story Mux (ADR-074).
export const MAX_STORY_DURATION_SECONDS = 60;
export const STORY_MAINTENANCE_BATCH_SIZE = 100;

// Rangée de stories : 100 comptes au plus, sans pagination.
export const MAX_TRAY_ACCOUNTS = 100;
export const DEFAULT_VIEWERS_PAGE_SIZE = 50;
export const MAX_VIEWERS_PAGE_SIZE = 100;

export function isSupportedStoryType(contentType: string): contentType is SupportedStoryType {
  return Object.hasOwn(SUPPORTED_STORY_TYPES, contentType);
}

export function mediaTypeOf(contentType: SupportedStoryType): StoryMediaType {
  return contentType === 'image/jpeg' ? 'photo' : 'video';
}

export function maxStorySize(mediaType: StoryMediaType): number {
  return mediaType === 'photo' ? MAX_STORY_PHOTO_SIZE_BYTES : MAX_STORY_VIDEO_SIZE_BYTES;
}

// Brut d'une story vidéo, sous le préfixe de l'auteur (suppression de compte) ; photo directement dans le bucket public.
export function storyRawKey(userId: string, storyId: string, contentType: SupportedStoryType): string {
  return mediaTypeOf(contentType) === 'photo' ? `${storyId}/photo.jpg` : `${userId}/stories/${storyId}.${SUPPORTED_STORY_TYPES[contentType]}`;
}

export function isValidStoryPhotoDimensions({ width, height }: ImageDimensions): boolean {
  return width * 16 === height * 9 && width >= STORY_PHOTO_MIN_WIDTH && width <= STORY_PHOTO_MAX_WIDTH;
}

// Contenu réel d'une photo envoyée : JPEG, 9:16, dans les dimensions acceptées.
export function isValidStoryPhoto(head: Uint8Array): boolean {
  const dimensions = readJpegDimensions(head);
  return dimensions !== null && isValidStoryPhotoDimensions(dimensions);
}

export function isActive(story: Story, now: Date): story is ActiveStory {
  return story.status === 'ready' && story.expiresAt !== null && story.expiresAt > now;
}

export function filesOf(story: Story): StoryFiles {
  return {
    storyId: story.id,
    mediaType: story.mediaType,
    rawKey: story.rawKey,
    uploadId: story.uploadId,
    ...(story.muxUploadId ? { muxUploadId: story.muxUploadId, muxAssetId: story.muxAssetId } : {}),
  };
}
