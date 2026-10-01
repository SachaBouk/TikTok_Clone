import { SuspendedAccounts } from './suspended-accounts';

// Adaptateur en mémoire pour les tests.
export class InMemorySuspendedAccounts extends SuspendedAccounts {
  private readonly ids: Set<string>;

  constructor(ids: string[] = []) {
    super();
    this.ids = new Set(ids);
  }

  async has(userId: string): Promise<boolean> {
    return this.ids.has(userId);
  }

  async all(): Promise<Set<string>> {
    return new Set(this.ids);
  }

  async add(userId: string): Promise<void> {
    this.ids.add(userId);
  }

  async remove(userId: string): Promise<void> {
    this.ids.delete(userId);
  }

  async replaceAll(userIds: string[]): Promise<void> {
    this.ids.clear();
    for (const id of userIds) this.ids.add(id);
  }
}
