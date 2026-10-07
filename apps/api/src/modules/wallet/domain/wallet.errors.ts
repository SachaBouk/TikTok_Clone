import { formatRetryDelay } from '../../../rate-limit/rate-limiter';

// Erreurs métier du module (cadeaux, ADR-050) : la couche `interfaces/` les traduit en codes HTTP.
export abstract class WalletError extends Error {}

// Code absent du catalogue : 400.
export class UnknownGiftError extends WalletError {
  constructor(code: string) {
    super(`Cadeau inconnu : ${code}`);
    this.name = 'UnknownGiftError';
  }
}

// Vidéo non publiée, supprimée, ou d'un compte suspendu : 404.
export class GiftVideoUnavailableError extends WalletError {
  constructor(videoId: string) {
    super(`Vidéo indisponible : ${videoId}`);
    this.name = 'GiftVideoUnavailableError';
  }
}

// Sa propre vidéo : 400.
export class CannotGiftYourselfError extends WalletError {
  constructor() {
    super('Impossible de s’offrir un cadeau');
    this.name = 'CannotGiftYourselfError';
  }
}

// Blocage dans un sens ou dans l'autre avec l'auteur (ADR-029) : 403, comme les réactions.
export class GiftBlockedError extends WalletError {
  constructor() {
    super('Action impossible avec ce compte');
    this.name = 'GiftBlockedError';
  }
}

// Solde insuffisant : 402.
export class InsufficientBalanceError extends WalletError {
  constructor(
    readonly balance: number,
    readonly price: number,
  ) {
    super(`Solde insuffisant : ${balance} jeton${balance > 1 ? 's' : ''}, il en faut ${price}`);
    this.name = 'InsufficientBalanceError';
  }
}

// Identifiant d'envoi déjà utilisé pour un autre cadeau ou une autre vidéo : 409.
export class GiftIdConflictError extends WalletError {
  constructor() {
    super('Identifiant d’envoi déjà utilisé pour un autre cadeau');
    this.name = 'GiftIdConflictError';
  }
}

// Limite de débit (ADR-050) : 429 avec Retry-After.
export class TooManyGiftsError extends WalletError {
  constructor(readonly retryAfterSeconds: number) {
    super(`Trop de cadeaux envoyés : réessayez dans ${formatRetryDelay(retryAfterSeconds)}`);
    this.name = 'TooManyGiftsError';
  }
}
