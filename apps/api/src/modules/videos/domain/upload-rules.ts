import type { RateLimitRule } from '../../../rate-limit/rate-limiter';

// Règles de l'upload direct (ADR-007), partagées par le service et la validation des requêtes.

// Formats produits par la galerie iOS. Le contenu réel est vérifié par le worker (ADR-008).
export const SUPPORTED_VIDEO_TYPES = {
  'video/mp4': 'mp4',
  'video/quicktime': 'mov',
} as const;
export type SupportedVideoType = keyof typeof SUPPORTED_VIDEO_TYPES;

export const MAX_VIDEO_SIZE_BYTES = 1024 ** 3; // 1 Gio

// Tout upload passe en multipart, même petit : un seul chemin côté app, et toute coupure est reprenable.
// S3 impose 5 Mio minimum par partie (sauf la dernière) et 10 000 parties maximum.
export const UPLOAD_PART_SIZE_BYTES = 10 * 1024 ** 2; // 10 Mio → 103 parties au maximum

// Validité des URLs signées : assez pour reprendre un upload interrompu sur réseau mobile.
export const UPLOAD_URL_TTL_SECONDS = 2 * 60 * 60;

export const MAX_DESCRIPTION_LENGTH = 2200;

// Envois démarrés par compte (ADR-039) : une vidéo coûte jusqu'à 1 Gio de stockage et un transcodage.
// Chaque `POST /videos/upload-url` compte, même si l'envoi est ensuite abandonné ou repris de zéro.
export const UPLOAD_RATE_LIMITS: RateLimitRule[] = [
  { limit: 10, windowSeconds: 3600 },
  { limit: 30, windowSeconds: 24 * 3600 },
];

// Clé du compteur des envois : partagée avec les stories vidéo (ADR-051), qui comptent dans la même limite.
export function uploadRateLimitKey(userId: string): string {
  return `upload:${userId}`;
}

export function isSupportedVideoType(contentType: string): contentType is SupportedVideoType {
  return Object.hasOwn(SUPPORTED_VIDEO_TYPES, contentType);
}

export function partCount(fileSize: number): number {
  return Math.max(1, Math.ceil(fileSize / UPLOAD_PART_SIZE_BYTES));
}
