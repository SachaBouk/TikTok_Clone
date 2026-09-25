import { Injectable } from '@nestjs/common';
import { Redis } from 'ioredis';
import { FeedSnapshot, FeedSnapshotStore } from '../domain/feed-snapshot.store';

const CURRENT_KEY = 'feed:snapshot:current';
const snapshotKey = (id: string) => `feed:snapshot:${id}`;

// Cache du feed dans Redis (ADR-014). Clés :
// - feed:snapshot:<id>      liste JSON des identifiants de vidéos, expire après la durée de vie de la photo ;
// - feed:snapshot:current   identifiant de la photo courante, expire au bout de l'intervalle de renouvellement.
@Injectable()
export class RedisFeedSnapshotStore extends FeedSnapshotStore {
  constructor(private readonly redis: Redis) {
    super();
  }

  async getCurrent(): Promise<FeedSnapshot | null> {
    const id = await this.redis.get(CURRENT_KEY);
    return id ? this.get(id) : null;
  }

  async get(id: string): Promise<FeedSnapshot | null> {
    const videoIds = await this.redis.get(snapshotKey(id));
    return videoIds ? { id, videoIds: JSON.parse(videoIds) as string[] } : null;
  }

  // La photo est écrite avant de devenir courante : une session ne peut pas pointer vers une photo absente.
  async save(snapshot: FeedSnapshot, currentForSeconds: number, ttlSeconds: number): Promise<void> {
    await this.redis
      .multi()
      .set(snapshotKey(snapshot.id), JSON.stringify(snapshot.videoIds), 'EX', ttlSeconds)
      .set(CURRENT_KEY, snapshot.id, 'EX', currentForSeconds)
      .exec();
  }
}
