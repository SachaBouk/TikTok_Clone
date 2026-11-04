import { PlusMembers } from './plus-members';

// Adaptateur en mémoire : tests, et valeur par défaut des services construits sans registre (personne n'est abonné).
export class InMemoryPlusMembers extends PlusMembers {
  private readonly expiries = new Map<string, Date>();

  constructor(entries: { userId: string; expiresAt: Date }[] = []) {
    super();
    for (const entry of entries) this.expiries.set(entry.userId, entry.expiresAt);
  }

  async expiryOf(userId: string): Promise<Date | null> {
    return this.expiries.get(userId) ?? null;
  }

  async expiriesOf(userIds: string[]): Promise<Map<string, Date>> {
    return new Map(userIds.flatMap((id) => (this.expiries.has(id) ? [[id, this.expiries.get(id)!] as const] : [])));
  }

  async set(userId: string, expiresAt: Date | null): Promise<void> {
    if (expiresAt) this.expiries.set(userId, expiresAt);
    else this.expiries.delete(userId);
  }

  async replaceAll(entries: { userId: string; expiresAt: Date }[]): Promise<void> {
    this.expiries.clear();
    for (const entry of entries) this.expiries.set(entry.userId, entry.expiresAt);
  }
}
