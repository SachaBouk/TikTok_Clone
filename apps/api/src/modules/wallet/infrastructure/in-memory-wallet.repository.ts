import { appliedAmount, type ApplyResult, type NewWalletEntry, type WalletTransaction } from '../domain/wallet';
import { WalletRepository } from '../domain/wallet.repository';

type StoredEntry = NewWalletEntry & { id: string; appliedAmount: number; balanceAfter: number | null };

// Adaptateur en mémoire pour les tests : même idempotence et même plancher à 0 que la base.
export class InMemoryWalletRepository extends WalletRepository {
  readonly balances = new Map<string, number>();
  readonly entries: StoredEntry[] = [];

  async getBalance(userId: string): Promise<number> {
    return this.balances.get(userId) ?? 0;
  }

  async apply(entry: NewWalletEntry): Promise<ApplyResult> {
    if (this.entries.some((e) => e.eventId === entry.eventId)) return { status: 'duplicate' };
    let applied = 0;
    let balance: number | null = null;
    if (entry.userId) {
      const current = this.balances.get(entry.userId) ?? 0;
      applied = appliedAmount(current, entry.amount);
      balance = current + applied;
      this.balances.set(entry.userId, balance);
    }
    // Identifiants croissants, comme les UUID v7 de la base.
    const id = `0192f3a0-0000-7000-8000-${String(this.entries.length + 1).padStart(12, '0')}`;
    this.entries.push({ ...entry, id, appliedAmount: applied, balanceAfter: balance });
    return { status: 'applied', appliedAmount: applied, balance };
  }

  async listTransactions(userId: string, beforeId: string | null, limit: number): Promise<WalletTransaction[]> {
    return this.entries
      .filter((e) => e.userId === userId && (!beforeId || e.id < beforeId))
      .sort((a, b) => (a.id < b.id ? 1 : -1))
      .slice(0, limit)
      .map((e) => ({ id: e.id, kind: e.kind, amount: e.appliedAmount, balanceAfter: e.balanceAfter ?? 0, productId: e.productId, occurredAt: e.occurredAt }));
  }
}
