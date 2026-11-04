import type { PlusSubscription } from '../domain/plus-subscription';
import { PlusSubscriptionRepository } from '../domain/plus-subscription.repository';

// Adaptateur en mémoire pour les tests. `knownUsers` : comptes existants (null : tous).
export class InMemoryPlusSubscriptionRepository extends PlusSubscriptionRepository {
  readonly rows = new Map<string, PlusSubscription>();

  constructor(private readonly knownUsers: Set<string> | null = null) {
    super();
  }

  async find(userId: string): Promise<PlusSubscription | null> {
    const row = this.rows.get(userId);
    return row ? { ...row } : null;
  }

  async save(subscription: PlusSubscription): Promise<boolean> {
    if (this.knownUsers && !this.knownUsers.has(subscription.userId)) return false;
    this.rows.set(subscription.userId, { ...subscription });
    return true;
  }

  async listActive(now: Date): Promise<PlusSubscription[]> {
    return [...this.rows.values()].filter((row) => row.expiresAt > now).map((row) => ({ ...row }));
  }
}
