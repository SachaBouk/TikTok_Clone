// Erreurs métier du module : la couche `interfaces/` les traduit en codes HTTP.
export abstract class MessagingError extends Error {}

// Conversation inconnue (ou supprimée avec le compte de l'autre participant), ou dont le compte connecté
// n'est pas participant : on ne révèle pas son existence.
export class ConversationNotFoundError extends MessagingError {
  constructor(id: string) {
    super(`Conversation introuvable : ${id}`);
    this.name = 'ConversationNotFoundError';
  }
}

export class MessageNotFoundError extends MessagingError {
  constructor(id: string) {
    super(`Message introuvable : ${id}`);
    this.name = 'MessageNotFoundError';
  }
}

export class RecipientNotFoundError extends MessagingError {
  constructor(username: string) {
    super(`Utilisateur introuvable : @${username}`);
    this.name = 'RecipientNotFoundError';
  }
}

export class SharedVideoNotFoundError extends MessagingError {
  constructor(id: string) {
    super(`Vidéo introuvable : ${id}`);
    this.name = 'SharedVideoNotFoundError';
  }
}

// Story inconnue, expirée, masquée, ou qui n'est pas celle de l'autre participant (ADR-051) : 404.
export class RepliedStoryNotFoundError extends MessagingError {
  constructor(id: string) {
    super(`Story introuvable : ${id}`);
    this.name = 'RepliedStoryNotFoundError';
  }
}

export class CannotMessageYourselfError extends MessagingError {
  constructor() {
    super('Impossible de s’écrire à soi-même');
    this.name = 'CannotMessageYourselfError';
  }
}

export class EmptyMessageError extends MessagingError {
  constructor() {
    super('Le message est vide : texte ou vidéo attendu');
    this.name = 'EmptyMessageError';
  }
}

// L'un des deux comptes a bloqué l'autre. Le message ne dit pas qui.
export class BlockedConversationError extends MessagingError {
  constructor() {
    super('Impossible d’écrire à ce compte');
    this.name = 'BlockedConversationError';
  }
}

export class RequestLimitReachedError extends MessagingError {
  constructor(limit: number) {
    super(`Demande de message en attente : ${limit} messages au plus avant qu’elle soit acceptée`);
    this.name = 'RequestLimitReachedError';
  }
}

export class NotMessageSenderError extends MessagingError {
  constructor() {
    super('Seul l’expéditeur peut retirer son message');
    this.name = 'NotMessageSenderError';
  }
}

// Accepter ou refuser une conversation qui n'est pas une demande reçue en attente.
export class NotAPendingRequestError extends MessagingError {
  constructor() {
    super('Cette conversation n’est pas une demande reçue en attente');
    this.name = 'NotAPendingRequestError';
  }
}

// Identifiant d'envoi (ADR-044) déjà utilisé par l'expéditeur dans une autre conversation : erreur de l'app.
export class ClientMessageIdConflictError extends MessagingError {
  constructor() {
    super('Identifiant d’envoi déjà utilisé pour un autre message');
    this.name = 'ClientMessageIdConflictError';
  }
}

export class RateLimitedError extends MessagingError {
  constructor(readonly retryAfterSeconds: number) {
    super(`Trop de messages envoyés : réessayez dans ${retryAfterSeconds} s`);
    this.name = 'RateLimitedError';
  }
}
