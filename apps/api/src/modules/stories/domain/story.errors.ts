import { formatRetryDelay } from '../../../rate-limit/rate-limiter';
import { MAX_ACTIVE_STORIES, MAX_STORY_PHOTO_SIZE_BYTES, MAX_STORY_VIDEO_SIZE_BYTES, STORY_PHOTO_MAX_WIDTH, STORY_PHOTO_MIN_WIDTH } from './story';

// Erreurs métier du module : la couche `interfaces/` les traduit en codes HTTP.
export abstract class StoryError extends Error {}

// Story inconnue, expirée, masquée au lecteur, ou d'un autre compte pour une action réservée à l'auteur : 404.
export class StoryNotFoundError extends StoryError {
  constructor(id: string) {
    super(`Story introuvable : ${id}`);
    this.name = 'StoryNotFoundError';
  }
}

// Compte inconnu (stories d'un profil) : 404.
export class StoryAuthorNotFoundError extends StoryError {
  constructor(username: string) {
    super(`Compte introuvable : ${username}`);
    this.name = 'StoryAuthorNotFoundError';
  }
}

export class UnsupportedStoryTypeError extends StoryError {
  constructor(contentType: string) {
    super(`Format non pris en charge : ${contentType}. Formats acceptés : vidéo MP4 ou MOV, photo JPEG`);
    this.name = 'UnsupportedStoryTypeError';
  }
}

export class StoryTooLargeError extends StoryError {
  constructor(photo: boolean) {
    super(`Fichier trop volumineux (maximum ${(photo ? MAX_STORY_PHOTO_SIZE_BYTES : MAX_STORY_VIDEO_SIZE_BYTES) / 1024 ** 2} Mio)`);
    this.name = 'StoryTooLargeError';
  }
}

// 30 stories actives au plus (ADR-051) : 409.
export class TooManyActiveStoriesError extends StoryError {
  constructor() {
    super(`Tu as déjà ${MAX_ACTIVE_STORIES} stories en ligne : attends qu’une expire ou supprimes-en une`);
    this.name = 'TooManyActiveStoriesError';
  }
}

// L'envoi a déjà été confirmé (ou la story a échoué) : 409.
export class StoryNotAwaitingUploadError extends StoryError {
  constructor(id: string) {
    super(`La story ${id} n'attend plus d'envoi`);
    this.name = 'StoryNotAwaitingUploadError';
  }
}

// Parties manquantes ou ETags incorrects : renvoyer les parties puis confirmer à nouveau. 400.
export class StoryUploadIncompleteError extends StoryError {
  constructor(detail?: string) {
    super(`Envoi incomplet${detail ? ` : ${detail}` : ''}`);
    this.name = 'StoryUploadIncompleteError';
  }
}

// Photo reçue qui n'est pas un JPEG 9:16 aux dimensions acceptées : supprimée, story en échec. 400.
export class InvalidStoryPhotoError extends StoryError {
  constructor() {
    super(
      `La photo doit être une image JPEG au format 9:16, de ${STORY_PHOTO_MIN_WIDTH}×${(STORY_PHOTO_MIN_WIDTH * 16) / 9} ` +
        `à ${STORY_PHOTO_MAX_WIDTH}×${(STORY_PHOTO_MAX_WIDTH * 16) / 9} px`,
    );
    this.name = 'InvalidStoryPhotoError';
  }
}

// On ne voit ni n'aime sa propre story : 400.
export class OwnStoryError extends StoryError {
  constructor() {
    super('Action impossible sur ta propre story');
    this.name = 'OwnStoryError';
  }
}

export class InvalidStoryCursorError extends StoryError {
  constructor() {
    super('Curseur invalide');
    this.name = 'InvalidStoryCursorError';
  }
}

// Limite de débit (ADR-039) : 429 avec Retry-After.
export class TooManyStoryActionsError extends StoryError {
  constructor(
    readonly retryAfterSeconds: number,
    what: 'uploads' | 'likes',
  ) {
    super(`${what === 'uploads' ? 'Trop de stories publiées' : 'Trop de likes'} récemment : réessayez dans ${formatRetryDelay(retryAfterSeconds)}`);
    this.name = 'TooManyStoryActionsError';
  }
}
