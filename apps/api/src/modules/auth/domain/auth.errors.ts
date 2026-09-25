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
