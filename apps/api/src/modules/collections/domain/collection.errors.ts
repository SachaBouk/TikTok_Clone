import { MAX_COLLECTION_BATCH, MAX_COLLECTION_NAME_LENGTH, MAX_COLLECTIONS_PER_ACCOUNT } from './collection';

// Erreurs métier : la couche `interfaces/` les traduit en codes HTTP (CollectionErrorFilter).
export abstract class CollectionError extends Error {}

// Inconnue, à un autre compte (modification), ou privée et lue par un autre : 404.
export class CollectionNotFoundError extends CollectionError {
  constructor(id: string) {
    super(`Collection introuvable : ${id}`);
    this.name = 'CollectionNotFoundError';
  }
}

export class InvalidCollectionNameError extends CollectionError {
  constructor() {
    super(`Le nom d’une collection fait de 1 à ${MAX_COLLECTION_NAME_LENGTH} caractères.`);
    this.name = 'InvalidCollectionNameError';
  }
}

export class TooManyCollectionVideosError extends CollectionError {
  constructor() {
    super(`${MAX_COLLECTION_BATCH} vidéos au plus par requête.`);
    this.name = 'TooManyCollectionVideosError';
  }
}

export class TooManyCollectionsError extends CollectionError {
  constructor() {
    super(`Tu as déjà ${MAX_COLLECTIONS_PER_ACCOUNT} collections.`);
    this.name = 'TooManyCollectionsError';
  }
}
