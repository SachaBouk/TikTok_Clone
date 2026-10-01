// Erreurs métier du module : la couche `interfaces/` les traduit en codes HTTP.
export abstract class AuthError extends Error {}

// Message volontairement identique pour un email inconnu et un mauvais mot de passe.
export class InvalidCredentialsError extends AuthError {
  constructor() {
    super('Email ou mot de passe incorrect');
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

// Trop d'échecs de connexion récents pour cet email ou depuis cette adresse IP (ADR-030) : 429 avec Retry-After.
// Le message ne dit pas laquelle des deux limites est atteinte.
export class TooManyLoginAttemptsError extends AuthError {
  constructor(readonly retryAfterSeconds: number) {
    super(`Trop de tentatives de connexion : réessayez dans ${formatDelay(retryAfterSeconds)}`);
    this.name = 'TooManyLoginAttemptsError';
  }
}

function formatDelay(seconds: number): string {
  return seconds < 60 ? `${seconds} s` : `${Math.ceil(seconds / 60)} min`;
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
