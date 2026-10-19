import { formatRetryDelay } from '../../../rate-limit/rate-limiter';

// Erreurs métier du module : la couche `interfaces/` les traduit en codes HTTP.
export abstract class InteractionError extends Error {}

// Trop d'actions récentes de ce type (ADR-039) : 429 avec Retry-After.
export type LimitedAction = 'reaction' | 'comment' | 'follow';
const LIMITED_ACTIONS: Record<LimitedAction, string> = {
  reaction: 'Trop de réactions',
  comment: 'Trop de commentaires',
  follow: 'Trop d’abonnements',
};
export class TooManyActionsError extends InteractionError {
  constructor(
    readonly action: LimitedAction,
    readonly retryAfterSeconds: number,
  ) {
    super(`${LIMITED_ACTIONS[action]} en peu de temps : réessayez dans ${formatRetryDelay(retryAfterSeconds)}`);
    this.name = 'TooManyActionsError';
  }
}

// Vidéo inexistante ou pas encore publiée : on ne réagit qu'à une vidéo visible de tous.
export class VideoNotAvailableError extends InteractionError {
  constructor(videoId: string) {
    super(`Vidéo introuvable : ${videoId}`);
    this.name = 'VideoNotAvailableError';
  }
}

// Compte à suivre ou à bloquer introuvable.
export class TargetUserNotFoundError extends InteractionError {
  constructor(username: string) {
    super(`Utilisateur introuvable : @${username}`);
    this.name = 'TargetUserNotFoundError';
  }
}

export class CannotFollowYourselfError extends InteractionError {
  constructor() {
    super('Impossible de se suivre soi-même');
    this.name = 'CannotFollowYourselfError';
  }
}

export class CannotBlockYourselfError extends InteractionError {
  constructor() {
    super('Impossible de se bloquer soi-même');
    this.name = 'CannotBlockYourselfError';
  }
}

// L'un des deux comptes a bloqué l'autre : ni follow, ni like, ni commentaire, ni republication entre eux.
// Le message ne dit pas qui a bloqué qui.
export class BlockedError extends InteractionError {
  constructor() {
    super('Action impossible avec ce compte');
    this.name = 'BlockedError';
  }
}

// L'auteur de la vidéo a coupé les commentaires (ADR-062) : personne ne peut commenter, répondre ni aimer un commentaire.
export class CommentsDisabledError extends InteractionError {
  constructor() {
    super('Les commentaires sont désactivés pour cette vidéo.');
    this.name = 'CommentsDisabledError';
  }
}

export class CommentNotFoundError extends InteractionError {
  constructor(id: string) {
    super(`Commentaire introuvable : ${id}`);
    this.name = 'CommentNotFoundError';
  }
}

export class NotCommentAuthorError extends InteractionError {
  constructor() {
    super("Seul l'auteur du commentaire ou de la vidéo peut le supprimer");
    this.name = 'NotCommentAuthorError';
  }
}

export class EmptyCommentError extends InteractionError {
  constructor() {
    super('Le commentaire est vide');
    this.name = 'EmptyCommentError';
  }
}

export class InvalidFollowCursorError extends InteractionError {
  constructor() {
    super('Curseur de liste invalide');
    this.name = 'InvalidFollowCursorError';
  }
}
