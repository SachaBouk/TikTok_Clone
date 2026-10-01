// Erreurs métier : la couche `interfaces/` les traduit en codes HTTP (UserErrorFilter).
export abstract class UserError extends Error {}

export class UserNotFoundError extends UserError {
  constructor(identifier: string) {
    super(`Utilisateur introuvable : ${identifier}`);
    this.name = 'UserNotFoundError';
  }
}

export class UsernameTakenError extends UserError {
  constructor(username: string) {
    super(`Le pseudo @${username} est déjà pris`);
    this.name = 'UsernameTakenError';
  }
}

export class InvalidProfileError extends UserError {
  constructor(reason: string) {
    super(reason);
    this.name = 'InvalidProfileError';
  }
}

// La photo annoncée n'a pas été envoyée au stockage (ou a déjà été remplacée).
export class AvatarNotUploadedError extends UserError {
  constructor() {
    super('Photo de profil introuvable : l’envoi n’a pas eu lieu ou a expiré');
    this.name = 'AvatarNotUploadedError';
  }
}

// Fichier envoyé qui n'est pas une image JPEG ou PNG valide, ou trop gros.
export class InvalidAvatarError extends UserError {
  constructor() {
    super('La photo de profil doit être une image JPEG ou PNG de 5 Mio au plus');
    this.name = 'InvalidAvatarError';
  }
}

// Compte suspendu par un administrateur (ADR-037) : son profil public n'est plus lisible (410).
export class ProfileSuspendedError extends UserError {
  constructor(username: string) {
    super(`Compte suspendu : @${username}`);
    this.name = 'ProfileSuspendedError';
  }
}
