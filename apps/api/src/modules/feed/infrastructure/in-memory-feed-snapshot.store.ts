import { FeedSnapshot, FeedSnapshotStore } from '../domain/feed-snapshot.store';

// Adaptateur en mémoire pour les tests. Les expirations sont simulées par `expireCurrent` / `expire`.
export class InMemoryFeedSnapshotStore extends FeedSnapshotStore {
  readonly snapshots = new Map<string, FeedSnapshot>();
  private currentId: string | null = null;

  async getCurrent(): Promise<FeedSnapshot | null> {
    return this.currentId ? this.get(this.currentId) : null;
  }

  async get(id: string): Promise<FeedSnapshot | null> {
    return this.snapshots.get(id) ?? null;
  }

  async save(snapshot: FeedSnapshot): Promise<void> {
    this.snapshots.set(snapshot.id, snapshot);
    this.currentId = snapshot.id;
  }

  // Fin de l'intervalle de renouvellement : la prochaine nouvelle session prendra une nouvelle photo.
  expireCurrent() {
    this.currentId = null;
  }

  // Fin de la durée de vie d'une photo : les sessions qui l'utilisent repartent sur un nouvel ordre.
  expire(id: string) {
    this.snapshots.delete(id);
    if (this.currentId === id) this.currentId = null;
  }
}
