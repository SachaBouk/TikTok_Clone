import { randomUUID } from 'node:crypto';
import { type Collection, COLLECTION_COVER_CANDIDATES, type CollectionVideoRow, type CollectionVisibility } from '../domain/collection';
import { CollectionRepository } from '../domain/collection.repository';

type StoredCollection = Omit<Collection, 'videosCount' | 'recentVideoIds'>;

// Adaptateur en mémoire du port, pour tester le service sans base (ADR-003). `isFavorite` reproduit la clé étrangère
// vers `favorites` : ajouter un non-favori échoue, et un favori retiré disparaît des collections (cascade).
export class InMemoryCollectionRepository extends CollectionRepository {
  private readonly collections = new Map<string, StoredCollection>();
  private readonly videos = new Map<string, Map<string, Date>>();
  private tick = 0;

  constructor(private readonly isFavorite: (userId: string, videoId: string) => boolean = () => true) {
    super();
  }

  // Date strictement croissante : ordres déterministes.
  private now(): Date {
    return new Date(Date.UTC(2026, 0, 1) + ++this.tick * 1000);
  }

  async create(userId: string, name: string, visibility: CollectionVisibility): Promise<Collection> {
    const at = this.now();
    // Identifiants ordonnés dans le temps, comme les UUID v7.
    const id = `${String(this.tick).padStart(8, '0')}-${randomUUID().slice(9)}`;
    this.collections.set(id, { id, userId, name, visibility, createdAt: at, updatedAt: at });
    this.videos.set(id, new Map());
    return this.toCollection(this.collections.get(id)!);
  }

  async findById(id: string): Promise<Collection | null> {
    const stored = this.collections.get(id);
    return stored ? this.toCollection(stored) : null;
  }

  async findByIds(ids: string[]): Promise<Collection[]> {
    return ids.flatMap((id) => {
      const stored = this.collections.get(id);
      return stored ? [this.toCollection(stored)] : [];
    });
  }

  async listByOwner(userId: string, onlyPublic: boolean): Promise<Collection[]> {
    return [...this.collections.values()]
      .filter((c) => c.userId === userId && (!onlyPublic || c.visibility === 'public'))
      .sort((a, b) => b.updatedAt.getTime() - a.updatedAt.getTime() || (a.id < b.id ? 1 : -1))
      .map((c) => this.toCollection(c));
  }

  async countByOwner(userId: string): Promise<number> {
    return [...this.collections.values()].filter((c) => c.userId === userId).length;
  }

  async update(id: string, changes: { name?: string; visibility?: CollectionVisibility }): Promise<Collection | null> {
    const stored = this.collections.get(id);
    if (!stored) return null;
    Object.assign(stored, changes);
    return this.toCollection(stored);
  }

  async delete(id: string): Promise<boolean> {
    this.videos.delete(id);
    return this.collections.delete(id);
  }

  async addVideos(id: string, userId: string, videoIds: string[]): Promise<void> {
    const videos = this.videos.get(id);
    const stored = this.collections.get(id);
    if (!videos || !stored) return;
    for (const videoId of videoIds) {
      if (!this.isFavorite(userId, videoId)) throw new Error(`Clé étrangère : ${videoId} n’est pas un favori de ${userId}`);
      if (!videos.has(videoId)) videos.set(videoId, this.now());
    }
    stored.updatedAt = this.now();
  }

  async removeVideos(id: string, videoIds: string[]): Promise<void> {
    for (const videoId of videoIds) this.videos.get(id)?.delete(videoId);
  }

  async listVideos(id: string, after: CollectionVideoRow | null, limit: number): Promise<CollectionVideoRow[]> {
    return this.rows(id)
      .filter((row) => !after || row.addedAt < after.addedAt || (row.addedAt.getTime() === after.addedAt.getTime() && row.videoId < after.videoId))
      .slice(0, limit);
  }

  async findContaining(userId: string, videoId: string): Promise<Set<string>> {
    return new Set([...this.collections.values()].filter((c) => c.userId === userId && this.videos.get(c.id)?.has(videoId)).map((c) => c.id));
  }

  // Lignes encore valables : la cascade de la clé étrangère retire celles dont le favori a disparu.
  private rows(id: string): CollectionVideoRow[] {
    const userId = this.collections.get(id)?.userId ?? '';
    return [...(this.videos.get(id) ?? new Map<string, Date>()).entries()]
      .filter(([videoId]) => this.isFavorite(userId, videoId))
      .map(([videoId, addedAt]) => ({ videoId, addedAt }))
      .sort((a, b) => b.addedAt.getTime() - a.addedAt.getTime() || (a.videoId < b.videoId ? 1 : -1));
  }

  private toCollection(stored: StoredCollection): Collection {
    const rows = this.rows(stored.id);
    return { ...stored, videosCount: rows.length, recentVideoIds: rows.slice(0, COLLECTION_COVER_CANDIDATES).map((r) => r.videoId) };
  }
}
