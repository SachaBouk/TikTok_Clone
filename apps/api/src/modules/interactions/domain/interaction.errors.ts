// Erreurs métier du module : la couche `interfaces/` les traduit en codes HTTP.
export abstract class InteractionError extends Error {}

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

export class CommentNotFoundError extends InteractionError {
  constructor(id: string) {
    super(`Commentaire introuvable : ${id}`);
    this.name = 'CommentNotFoundError';
  }
}

export class NotCommentAuthorError extends InteractionError {
  constructor() {
    super("Seul l'auteur d'un commentaire peut le supprimer");
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
