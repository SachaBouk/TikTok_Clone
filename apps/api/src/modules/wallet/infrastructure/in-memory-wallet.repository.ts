import {
  appliedAmount,
  type ApplyResult,
  type LedgerFilter,
  type NewWalletEntry,
  PRODUCTION_ENVIRONMENT,
  type TokenTotals,
  type WalletLedgerEntry,
  type WalletStats,
  type WalletTransaction,
} from '../domain/wallet';
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
      .map((e) => ({
        id: e.id,
        kind: e.kind,
        amount: e.appliedAmount,
        balanceAfter: e.balanceAfter ?? 0,
        productId: e.productId,
        occurredAt: e.occurredAt,
      }));
  }

  async getBalances(userIds: string[]): Promise<Map<string, number>> {
    return new Map(userIds.flatMap((id) => (this.balances.has(id) ? [[id, this.balances.get(id)!] as const] : [])));
  }

  async listLedger(filter: LedgerFilter, beforeId: string | null, limit: number): Promise<WalletLedgerEntry[]> {
    return this.entries
      .filter(
        (e) => (!filter.userId || e.userId === filter.userId) && (!filter.unmatched || e.balanceAfter === null) && (!beforeId || e.id < beforeId),
      )
      .sort((a, b) => (a.id < b.id ? 1 : -1))
      .slice(0, limit)
      .map((e) => ({
        id: e.id,
        userId: e.userId,
        kind: e.kind,
        amount: e.amount,
        appliedAmount: e.appliedAmount,
        balanceAfter: e.balanceAfter,
        unmatched: e.balanceAfter === null,
        revenuecatEventId: e.eventId,
        appUserId: e.appUserId,
        productId: e.productId,
        storeTransactionId: e.storeTransactionId,
        store: e.store,
        environment: e.environment,
        occurredAt: e.occurredAt,
      }));
  }

  async getStats(since: Date): Promise<WalletStats> {
    const totals = (production: boolean): TokenTotals => {
      const sum = (kind: string) =>
        this.entries
          .filter((e) => e.kind === kind && (e.environment === PRODUCTION_ENVIRONMENT) === production)
          .reduce((total, e) => total + e.amount, 0);
      return { purchased: sum('purchase'), refunded: Math.abs(sum('refund')), adjusted: sum('adjustment') };
    };
    return {
      production: totals(true),
      sandbox: totals(false),
      purchasedSince: this.entries
        .filter((e) => e.kind === 'purchase' && e.environment === PRODUCTION_ENVIRONMENT && e.occurredAt >= since)
        .reduce((total, e) => total + e.amount, 0),
      inCirculation: [...this.balances.values()].reduce((total, balance) => total + balance, 0),
      unmatched: this.entries.filter((e) => e.balanceAfter === null).length,
    };
  }
}
