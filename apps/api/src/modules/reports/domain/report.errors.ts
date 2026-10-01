// Erreurs métier du module : la couche `interfaces/` les traduit en codes HTTP (ReportErrorFilter).
export abstract class ReportError extends Error {}

// Contenu introuvable ou invisible pour la personne (supprimé, non publié, compte suspendu) : 404.
export class ReportTargetNotFoundError extends ReportError {
  constructor() {
    super('Contenu introuvable');
    this.name = 'ReportTargetNotFoundError';
  }
}

// On ne signale ni son propre compte ni son propre contenu : 400.
export class CannotReportYourselfError extends ReportError {
  constructor() {
    super('Tu ne peux pas signaler ton propre contenu');
    this.name = 'CannotReportYourselfError';
  }
}

// Trop de signalements récents : 429 avec Retry-After.
export class TooManyReportsError extends ReportError {
  constructor(readonly retryAfterSeconds: number) {
    super('Trop de signalements envoyés : réessaie plus tard');
    this.name = 'TooManyReportsError';
  }
}

// Requête invalide (précision trop longue) : 400.
export class InvalidReportError extends ReportError {
  constructor(reason: string) {
    super(reason);
    this.name = 'InvalidReportError';
  }
}
