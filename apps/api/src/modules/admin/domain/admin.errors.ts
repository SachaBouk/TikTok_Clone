// Erreurs métier du module : la couche `interfaces/` les traduit en codes HTTP (AdminErrorFilter).
// Les erreurs des autres modules (compte, vidéo, commentaire introuvables) sont traduites en celles-ci.
export abstract class AdminError extends Error {}

export class AdminTargetNotFoundError extends AdminError {
  constructor(kind: 'Compte' | 'Vidéo' | 'Commentaire', id: string) {
    super(`${kind} introuvable : ${id}`);
    this.name = 'AdminTargetNotFoundError';
  }
}
