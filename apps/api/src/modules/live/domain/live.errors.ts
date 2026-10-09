import { formatRetryDelay } from '../../../rate-limit/rate-limiter';
import { MAX_HEARTS_PER_BATCH, MAX_LIVE_MESSAGE_LENGTH, MAX_LIVE_TITLE_LENGTH } from './live';

// Erreurs métier du module : la couche `interfaces/` les traduit en codes HTTP.
export abstract class LiveError extends Error {}

// Live inconnu, masqué au lecteur (blocage, auteur suspendu), ou d'un autre compte pour une action réservée à l'auteur : 404.
export class LiveNotFoundError extends LiveError {
  constructor(id: string) {
    super(`Live introuvable : ${id}`);
    this.name = 'LiveNotFoundError';
  }
}

// Le live est terminé : on ne peut plus le rejoindre ni y écrire. 409.
export class LiveEndedError extends LiveError {
  constructor() {
    super('Ce live est terminé');
    this.name = 'LiveEndedError';
  }
}

// Message du chat inconnu, ou d'un autre live : 404.
export class LiveMessageNotFoundError extends LiveError {
  constructor(id: string) {
    super(`Message introuvable : ${id}`);
    this.name = 'LiveMessageNotFoundError';
  }
}

// Retrait d'un message par quelqu'un qui n'en est ni l'auteur ni l'auteur du live : 403.
export class LiveMessageForbiddenError extends LiveError {
  constructor() {
    super('Seuls l’auteur du message et celui du live peuvent le retirer');
    this.name = 'LiveMessageForbiddenError';
  }
}

export class InvalidLiveTitleError extends LiveError {
  constructor() {
    super(`Le titre fait au plus ${MAX_LIVE_TITLE_LENGTH} caractères`);
    this.name = 'InvalidLiveTitleError';
  }
}

export class InvalidLiveMessageError extends LiveError {
  constructor() {
    super(`Un message fait de 1 à ${MAX_LIVE_MESSAGE_LENGTH} caractères`);
    this.name = 'InvalidLiveMessageError';
  }
}

export class InvalidHeartsCountError extends LiveError {
  constructor() {
    super(`De 1 à ${MAX_HEARTS_PER_BATCH} cœurs par envoi`);
    this.name = 'InvalidHeartsCountError';
  }
}

// On n'envoie pas de cœurs à son propre live : 400.
export class OwnLiveError extends LiveError {
  constructor() {
    super('Action impossible sur ton propre live');
    this.name = 'OwnLiveError';
  }
}

// Le serveur vidéo n'a pas pu ouvrir la salle : 503, rien n'est gardé.
export class LiveMediaUnavailableError extends LiveError {
  constructor() {
    super('Le service de live est indisponible pour le moment. Réessaie plus tard.');
    this.name = 'LiveMediaUnavailableError';
  }
}

// Limite de débit (ADR-039) : 429 avec Retry-After.
export class TooManyLiveActionsError extends LiveError {
  constructor(
    readonly retryAfterSeconds: number,
    what: 'starts' | 'messages' | 'hearts',
  ) {
    const label = { starts: 'Trop de lives lancés', messages: 'Trop de messages envoyés', hearts: 'Trop de cœurs envoyés' }[what];
    super(`${label} récemment : réessayez dans ${formatRetryDelay(retryAfterSeconds)}`);
    this.name = 'TooManyLiveActionsError';
  }
}
