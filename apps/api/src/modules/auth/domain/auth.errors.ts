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
