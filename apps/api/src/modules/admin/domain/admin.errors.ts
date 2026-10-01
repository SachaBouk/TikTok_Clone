// Erreurs métier du module : la couche `interfaces/` les traduit en codes HTTP (AdminErrorFilter).
// Les erreurs des autres modules (compte, vidéo, commentaire introuvables) sont traduites en celles-ci.
export abstract class AdminError extends Error {}

export class AdminTargetNotFoundError extends AdminError {
  constructor(kind: 'Compte' | 'Vidéo' | 'Commentaire' | 'Signalement', id: string) {
    super(`${kind} introuvable : ${id}`);
    this.name = 'AdminTargetNotFoundError';
  }
}

// Action refusée par une règle d'un autre module (suspendre un administrateur, ADR-037) : 409.
export class AdminActionRefusedError extends AdminError {
  constructor(reason: string) {
    super(reason);
    this.name = 'AdminActionRefusedError';
  }
}
