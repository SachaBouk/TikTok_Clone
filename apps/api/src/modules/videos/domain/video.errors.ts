import { formatRetryDelay } from '../../../rate-limit/rate-limiter';

import { MAX_VIDEO_SIZE_BYTES, SUPPORTED_VIDEO_TYPES } from './upload-rules';

// Erreurs métier du module : la couche `interfaces/` les traduit en codes HTTP.
export abstract class VideoError extends Error {}

// Trop d'envois de vidéos démarrés récemment (ADR-039) : 429 avec Retry-After.
export class TooManyUploadsError extends VideoError {
  constructor(readonly retryAfterSeconds: number) {
    super(`Trop de vidéos envoyées récemment : réessayez dans ${formatRetryDelay(retryAfterSeconds)}`);
    this.name = 'TooManyUploadsError';
  }
}

export class VideoNotFoundError extends VideoError {
  constructor(id: string) {
    super(`Vidéo introuvable : ${id}`);
    this.name = 'VideoNotFoundError';
  }
}

export class UnsupportedVideoTypeError extends VideoError {
  constructor(contentType: string) {
    super(`Format non pris en charge : ${contentType}. Formats acceptés : ${Object.keys(SUPPORTED_VIDEO_TYPES).join(', ')}`);
    this.name = 'UnsupportedVideoTypeError';
  }
}

export class VideoTooLargeError extends VideoError {
  constructor() {
    super(`Vidéo trop volumineuse (maximum ${MAX_VIDEO_SIZE_BYTES / 1024 ** 2} Mio)`);
    this.name = 'VideoTooLargeError';
  }
}

// L'upload a déjà été confirmé (ou la vidéo a échoué) : il n'y a plus rien à confirmer.
export class VideoNotAwaitingUploadError extends VideoError {
  constructor(id: string) {
    super(`La vidéo ${id} n'attend plus d'upload`);
    this.name = 'VideoNotAwaitingUploadError';
  }
}

// Parties manquantes ou ETags incorrects : le client peut renvoyer les parties puis confirmer à nouveau.
export class UploadIncompleteError extends VideoError {
  constructor(detail?: string) {
    super(`Upload incomplet${detail ? ` : ${detail}` : ''}`);
    this.name = 'UploadIncompleteError';
  }
}

// Nom de hashtag invalide (ADR-049) : 400.
export class InvalidHashtagError extends VideoError {
  constructor(name: string) {
    super(`Hashtag invalide : ${name}`);
    this.name = 'InvalidHashtagError';
  }
}

// Son introuvable ou plus proposé (ADR-064 : vidéo d'origine supprimée, privée, ou qui ne le permet plus) : 404.
export class SoundNotFoundError extends VideoError {
  constructor(id: string) {
    super(`Son introuvable : ${id}`);
    this.name = 'SoundNotFoundError';
  }
}
