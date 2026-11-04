import type { Collection, CollectionVideoRow, CollectionVisibility } from './collection';

// Port (ADR-003) : classe abstraite, jeton d'injection NestJS sans que le domaine importe NestJS.
export abstract class CollectionRepository {
  abstract create(userId: string, name: string, visibility: CollectionVisibility): Promise<Collection>;
  abstract findById(id: string): Promise<Collection | null>;
  abstract findByIds(ids: string[]): Promise<Collection[]>;
  // Collections du compte (publiques seulement si `onlyPublic`), de la plus récemment utilisée à la plus ancienne.
  abstract listByOwner(userId: string, onlyPublic: boolean): Promise<Collection[]>;
  abstract countByOwner(userId: string): Promise<number>;
  // Renvoie la collection modifiée, ou null si elle n'existe plus.
  abstract update(id: string, changes: { name?: string; visibility?: CollectionVisibility }): Promise<Collection | null>;
  abstract delete(id: string): Promise<boolean>;
  // Ajoute des favoris de `userId` (déjà présents : ignorés) et avance `updated_at`.
  abstract addVideos(id: string, userId: string, videoIds: string[]): Promise<void>;
  abstract removeVideos(id: string, videoIds: string[]): Promise<void>;
  // Vidéos, de la plus récemment ajoutée à la plus ancienne, strictement après `after`.
  abstract listVideos(id: string, after: CollectionVideoRow | null, limit: number): Promise<CollectionVideoRow[]>;
  // Collections de `userId` qui contiennent `videoId`.
  abstract findContaining(userId: string, videoId: string): Promise<Set<string>>;
}
