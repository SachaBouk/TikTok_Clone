import { ReceivedLikesCounter } from '../domain/received-likes-counter';

// Adaptateur en mémoire pour les tests : likes reçus fixés par compte (0 par défaut).
export class InMemoryReceivedLikesCounter extends ReceivedLikesCounter {
  readonly counts = new Map<string, number>();

  async countFor(userId: string): Promise<number> {
    return this.counts.get(userId) ?? 0;
  }
}
