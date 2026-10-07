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
import type { Gift, NewGift, SendGiftResult, WalletAmounts } from '../domain/gift';
import { WalletRepository } from '../domain/wallet.repository';

type StoredEntry = NewWalletEntry & { id: string; appliedAmount: number; balanceAfter: number | null };

// Adaptateur en mémoire pour les tests : même idempotence et même plancher à 0 que la base.
export class InMemoryWalletRepository extends WalletRepository {
  readonly balances = new Map<string, number>();
  readonly earnings = new Map<string, number>();
  readonly entries: StoredEntry[] = [];
  readonly gifts: (Gift & { clientGiftId: string })[] = [];
  // Identifiants croissants, comme les UUID v7 de la base, partagés par le journal et les cadeaux (fusionnés par id).
  private sequence = 0;

  async getBalance(userId: string): Promise<number> {
    return this.balances.get(userId) ?? 0;
  }

  async getAmounts(userId: string): Promise<WalletAmounts> {
    return { balance: this.balances.get(userId) ?? 0, earned: this.earnings.get(userId) ?? 0 };
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
    this.entries.push({ ...entry, id: this.nextId(), appliedAmount: applied, balanceAfter: balance });
    return { status: 'applied', appliedAmount: applied, balance, earned: entry.userId ? (this.earnings.get(entry.userId) ?? 0) : null };
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
      gifts: {
        spent: this.gifts.reduce((total, gift) => total + gift.amount, 0),
        spentSince: this.gifts.filter((gift) => gift.createdAt >= since).reduce((total, gift) => total + gift.amount, 0),
        earned: [...this.earnings.values()].reduce((total, earned) => total + earned, 0),
      },
    };
  }

  async getEarnings(userIds: string[]): Promise<Map<string, number>> {
    return new Map(userIds.flatMap((id) => (this.earnings.has(id) ? [[id, this.earnings.get(id)!] as const] : [])));
  }

  async sendGift(gift: NewGift): Promise<SendGiftResult> {
    const existing = await this.findGiftByClientId(gift.senderId, gift.clientGiftId);
    if (existing) return { status: 'duplicate', gift: existing };
    const balance = this.balances.get(gift.senderId) ?? 0;
    if (balance < gift.amount) return { status: 'insufficientBalance', balance };
    const senderBalance = balance - gift.amount;
    this.balances.set(gift.senderId, senderBalance);
    const recipientEarned = (this.earnings.get(gift.recipientId) ?? 0) + gift.amount;
    this.earnings.set(gift.recipientId, recipientEarned);
    const stored = {
      id: this.nextId(),
      senderId: gift.senderId,
      recipientId: gift.recipientId,
      videoId: gift.videoId,
      giftCode: gift.giftCode,
      amount: gift.amount,
      senderBalanceAfter: senderBalance,
      clientGiftId: gift.clientGiftId,
      createdAt: new Date(Date.UTC(2026, 0, 1) + this.sequence * 1000),
    };
    this.gifts.push(stored);
    return { status: 'sent', gift: toGift(stored), senderBalance, recipientEarned };
  }

  async findGiftByClientId(senderId: string, clientGiftId: string): Promise<Gift | null> {
    const gift = this.gifts.find((g) => g.senderId === senderId && g.clientGiftId === clientGiftId);
    return gift ? toGift(gift) : null;
  }

  async listSentGifts(senderId: string, beforeId: string | null, limit: number): Promise<Gift[]> {
    return this.listGiftsWhere((g) => g.senderId === senderId, beforeId, limit);
  }

  async listReceivedGifts(recipientId: string, beforeId: string | null, limit: number): Promise<Gift[]> {
    return this.listGiftsWhere((g) => g.recipientId === recipientId, beforeId, limit);
  }

  async listGifts(filter: { userId?: string }, beforeId: string | null, limit: number): Promise<Gift[]> {
    return this.listGiftsWhere((g) => !filter.userId || g.senderId === filter.userId || g.recipientId === filter.userId, beforeId, limit);
  }

  // Reproduit les `SET NULL` de la base à la suppression d'un compte ou d'une vidéo.
  forget(id: string): void {
    for (const gift of this.gifts) {
      if (gift.senderId === id) gift.senderId = null;
      if (gift.recipientId === id) gift.recipientId = null;
      if (gift.videoId === id) gift.videoId = null;
    }
  }

  private listGiftsWhere(matches: (gift: Gift) => boolean, beforeId: string | null, limit: number): Gift[] {
    return this.gifts
      .filter((g) => matches(g) && (!beforeId || g.id < beforeId))
      .sort((a, b) => (a.id < b.id ? 1 : -1))
      .slice(0, limit)
      .map(toGift);
  }

  private nextId(): string {
    return `0192f3a0-0000-7000-8000-${String(++this.sequence).padStart(12, '0')}`;
  }
}

function toGift({ clientGiftId: _clientGiftId, ...gift }: Gift & { clientGiftId: string }): Gift {
  return { ...gift };
}
