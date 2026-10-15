import { formatRetryDelay } from '../../../rate-limit/rate-limiter';

// Erreurs métier du module : la couche `interfaces/` les traduit en codes HTTP.
export abstract class AuthError extends Error {}

// Message volontairement identique pour un identifiant inconnu et un mauvais mot de passe.
export class InvalidCredentialsError extends AuthError {
  constructor() {
    super('Identifiant ou mot de passe incorrect');
    this.name = 'InvalidCredentialsError';
  }
}

export class InvalidRefreshTokenError extends AuthError {
  constructor() {
    super('Session expirée ou invalide');
    this.name = 'InvalidRefreshTokenError';
  }
}

export class InvalidAppleTokenError extends AuthError {
  constructor() {
    super('Jeton Apple invalide');
    this.name = 'InvalidAppleTokenError';
  }
}

export class EmailAlreadyUsedError extends AuthError {
  constructor() {
    super('Un compte existe déjà avec cet email');
    this.name = 'EmailAlreadyUsedError';
  }
}

export class UsernameAlreadyUsedError extends AuthError {
  constructor(username: string) {
    super(`Le pseudo @${username} est déjà pris`);
    this.name = 'UsernameAlreadyUsedError';
  }
}

// Inscription refusée par ses règles (ADR-055) : date de naissance invalide, moins de 13 ans, mot de passe trop
// faible. 400.
export class InvalidRegistrationError extends AuthError {
  constructor(reason: string) {
    super(reason);
    this.name = 'InvalidRegistrationError';
  }
}

// Trop d'échecs de connexion récents pour cet email ou depuis cette adresse IP (ADR-030) : 429 avec Retry-After.
// Le message ne dit pas laquelle des deux limites est atteinte.
export class TooManyLoginAttemptsError extends AuthError {
  constructor(readonly retryAfterSeconds: number) {
    super(`Trop de tentatives de connexion : réessayez dans ${formatRetryDelay(retryAfterSeconds)}`);
    this.name = 'TooManyLoginAttemptsError';
  }
}

// Trop de comptes créés récemment depuis cette adresse IP (ADR-039) : 429 avec Retry-After.
export class TooManySignupsError extends AuthError {
  constructor(readonly retryAfterSeconds: number) {
    super(`Trop de comptes créés depuis cette connexion : réessayez dans ${formatRetryDelay(retryAfterSeconds)}`);
    this.name = 'TooManySignupsError';
  }
}

// Compte suspendu par un administrateur (ADR-037) : 403 à la connexion, avec un message générique (le motif reste
// interne). Levée seulement après vérification du mot de passe : la suspension n'est révélée qu'au titulaire.
export class AccountSuspendedError extends AuthError {
  constructor() {
    super('Compte suspendu');
    this.name = 'AccountSuspendedError';
  }
}

// Un administrateur ne peut pas être suspendu (retirer d'abord son rôle), ni se suspendre lui-même.
export class CannotSuspendAdminError extends AuthError {
  constructor() {
    super('Un administrateur ne peut pas être suspendu');
    this.name = 'CannotSuspendAdminError';
  }
}

export class InvalidSuspensionReasonError extends AuthError {
  constructor(maxLength: number) {
    super(`Le motif de la suspension est obligatoire (${maxLength} caractères au plus)`);
    this.name = 'InvalidSuspensionReasonError';
  }
}
