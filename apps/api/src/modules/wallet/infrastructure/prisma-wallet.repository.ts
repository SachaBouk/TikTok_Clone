import { Injectable } from '@nestjs/common';
import { violatedUniqueConstraint } from '../../../database/prisma-errors';
import { PrismaService } from '../../../database/prisma.service';
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

const transactionSelect = { id: true, kind: true, appliedAmount: true, balanceAfter: true, productId: true, occurredAt: true } as const;

@Injectable()
export class PrismaWalletRepository extends WalletRepository {
  constructor(private readonly prisma: PrismaService) {
    super();
  }

  async getBalance(userId: string): Promise<number> {
    const wallet = await this.prisma.wallet.findUnique({ where: { userId }, select: { balance: true } });
    return wallet?.balance ?? 0;
  }

  // Une transaction par mouvement : la ligne du portefeuille est verrouillée (FOR UPDATE) le temps de calculer
  // le mouvement appliqué et le nouveau solde. Deux livraisons simultanées du même événement se suivent donc :
  // la seconde trouve la ligne du journal, ou bute sur son index unique (`revenuecat_event_id`).
  async apply(entry: NewWalletEntry): Promise<ApplyResult> {
    try {
      return await this.prisma.$transaction(async (tx) => {
        const existing = await tx.walletTransaction.findUnique({ where: { revenuecatEventId: entry.eventId }, select: { id: true } });
        if (existing) return { status: 'duplicate' as const };

        let applied = 0;
        let balance: number | null = null;
        let earned: number | null = null;
        if (entry.userId) {
          await tx.wallet.createMany({ data: [{ userId: entry.userId }], skipDuplicates: true });
          const [wallet] = await tx.$queryRaw<
            { balance: number; earned: number }[]
          >`SELECT balance, earned FROM wallets WHERE user_id = ${entry.userId}::uuid FOR UPDATE`;
          applied = appliedAmount(wallet.balance, entry.amount);
          balance = wallet.balance + applied;
          earned = wallet.earned;
          await tx.wallet.update({ where: { userId: entry.userId }, data: { balance } });
        }
        await tx.walletTransaction.create({
          data: {
            userId: entry.userId,
            kind: entry.kind,
            amount: entry.amount,
            appliedAmount: applied,
            balanceAfter: balance,
            revenuecatEventId: entry.eventId,
            appUserId: entry.appUserId,
            productId: entry.productId,
            storeTransactionId: entry.storeTransactionId,
            store: entry.store,
            environment: entry.environment,
            occurredAt: entry.occurredAt,
          },
        });
        return { status: 'applied' as const, appliedAmount: applied, balance, earned };
      });
    } catch (error) {
      if (violatedUniqueConstraint(error)?.includes('revenuecat_event_id')) return { status: 'duplicate' };
      throw error;
    }
  }

  async getAmounts(userId: string): Promise<WalletAmounts> {
    const wallet = await this.prisma.wallet.findUnique({ where: { userId }, select: { balance: true, earned: true } });
    return { balance: wallet?.balance ?? 0, earned: wallet?.earned ?? 0 };
  }

  async listTransactions(userId: string, beforeId: string | null, limit: number): Promise<WalletTransaction[]> {
    const rows = await this.prisma.walletTransaction.findMany({
      where: { userId, ...(beforeId ? { id: { lt: beforeId } } : {}) },
      orderBy: { id: 'desc' },
      take: limit,
      select: transactionSelect,
    });
    // Les lignes d'un compte ont toujours un solde (seules celles d'un acheteur inconnu n'en ont pas).
    return rows.map(({ appliedAmount: amount, balanceAfter, ...row }) => ({ ...row, amount, balanceAfter: balanceAfter ?? 0 }));
  }

  async getBalances(userIds: string[]): Promise<Map<string, number>> {
    if (userIds.length === 0) return new Map();
    const wallets = await this.prisma.wallet.findMany({ where: { userId: { in: userIds } }, select: { userId: true, balance: true } });
    return new Map(wallets.map((wallet) => [wallet.userId, wallet.balance]));
  }

  // Filtre « à rapprocher » : `balance_after` nul (aucun portefeuille touché). Peu de lignes, pas d'index dédié.
  async listLedger(filter: LedgerFilter, beforeId: string | null, limit: number): Promise<WalletLedgerEntry[]> {
    const rows = await this.prisma.walletTransaction.findMany({
      where: {
        ...(filter.userId ? { userId: filter.userId } : {}),
        ...(filter.unmatched ? { balanceAfter: null } : {}),
        ...(beforeId ? { id: { lt: beforeId } } : {}),
      },
      orderBy: { id: 'desc' },
      take: limit,
      select: {
        id: true,
        userId: true,
        kind: true,
        amount: true,
        appliedAmount: true,
        balanceAfter: true,
        revenuecatEventId: true,
        appUserId: true,
        productId: true,
        storeTransactionId: true,
        store: true,
        environment: true,
        occurredAt: true,
      },
    });
    return rows.map((row) => ({ ...row, unmatched: row.balanceAfter === null }));
  }

  async getStats(since: Date): Promise<WalletStats> {
    const [sums, recent, circulation, unmatched, spent, spentSince] = await Promise.all([
      this.prisma.walletTransaction.groupBy({ by: ['environment', 'kind'], _sum: { amount: true } }),
      this.prisma.walletTransaction.aggregate({
        where: { kind: 'purchase', environment: PRODUCTION_ENVIRONMENT, occurredAt: { gte: since } },
        _sum: { amount: true },
      }),
      this.prisma.wallet.aggregate({ _sum: { balance: true, earned: true } }),
      this.prisma.walletTransaction.count({ where: { balanceAfter: null } }),
      this.prisma.giftSent.aggregate({ _sum: { amount: true } }),
      this.prisma.giftSent.aggregate({ where: { createdAt: { gte: since } }, _sum: { amount: true } }),
    ]);
    const totals = (production: boolean): TokenTotals => {
      const sum = (kind: string) =>
        sums
          .filter((row) => row.kind === kind && (row.environment === PRODUCTION_ENVIRONMENT) === production)
          .reduce((total, row) => total + (row._sum.amount ?? 0), 0);
      return { purchased: sum('purchase'), refunded: Math.abs(sum('refund')), adjusted: sum('adjustment') };
    };
    return {
      production: totals(true),
      sandbox: totals(false),
      purchasedSince: recent._sum.amount ?? 0,
      inCirculation: circulation._sum.balance ?? 0,
      unmatched,
      gifts: { spent: spent._sum.amount ?? 0, spentSince: spentSince._sum.amount ?? 0, earned: circulation._sum.earned ?? 0 },
    };
  }

  async getEarnings(userIds: string[]): Promise<Map<string, number>> {
    if (userIds.length === 0) return new Map();
    const wallets = await this.prisma.wallet.findMany({ where: { userId: { in: userIds } }, select: { userId: true, earned: true } });
    return new Map(wallets.map((wallet) => [wallet.userId, wallet.earned]));
  }

  async sendGift(gift: NewGift): Promise<SendGiftResult> {
    try {
      return await this.prisma.$transaction(async (tx) => {
        const existing = await tx.giftSent.findUnique({
          where: { senderId_clientGiftId: { senderId: gift.senderId, clientGiftId: gift.clientGiftId } },
          select: giftSelect,
        });
        if (existing) return { status: 'duplicate' as const, gift: existing };
        await tx.wallet.createMany({ data: [{ userId: gift.senderId }, { userId: gift.recipientId }], skipDuplicates: true });
        // Verrous pris dans l'ordre des identifiants : deux cadeaux croisés (A → B, B → A) se suivent sans s'interbloquer.
        const wallets = await tx.$queryRaw<{ user_id: string; balance: number }[]>`
          SELECT user_id::text AS user_id, balance FROM wallets
          WHERE user_id IN (${gift.senderId}::uuid, ${gift.recipientId}::uuid)
          ORDER BY user_id FOR UPDATE`;
        const balance = wallets.find((wallet) => wallet.user_id === gift.senderId)?.balance ?? 0;
        if (balance < gift.amount) return { status: 'insufficientBalance' as const, balance };
        const senderBalance = balance - gift.amount;
        await tx.wallet.update({ where: { userId: gift.senderId }, data: { balance: senderBalance } });
        const recipient = await tx.wallet.update({
          where: { userId: gift.recipientId },
          data: { earned: { increment: gift.amount } },
          select: { earned: true },
        });
        const created = await tx.giftSent.create({ data: { ...gift, senderBalanceAfter: senderBalance }, select: giftSelect });
        return { status: 'sent' as const, gift: created, senderBalance, recipientEarned: recipient.earned };
      });
    } catch (error) {
      // Deux envois simultanés avec le même identifiant : l'index unique n'en laisse passer qu'un.
      if (violatedUniqueConstraint(error)?.includes('client_gift_id')) {
        const existing = await this.findGiftByClientId(gift.senderId, gift.clientGiftId);
        if (existing) return { status: 'duplicate', gift: existing };
      }
      throw error;
    }
  }

  findGiftByClientId(senderId: string, clientGiftId: string): Promise<Gift | null> {
    return this.prisma.giftSent.findUnique({ where: { senderId_clientGiftId: { senderId, clientGiftId } }, select: giftSelect });
  }

  // Index (sender_id, gift_id) et (recipient_id, gift_id).
  listSentGifts(senderId: string, beforeId: string | null, limit: number): Promise<Gift[]> {
    return this.prisma.giftSent.findMany({
      where: { senderId, ...(beforeId ? { id: { lt: beforeId } } : {}) },
      orderBy: { id: 'desc' },
      take: limit,
      select: giftSelect,
    });
  }

  listReceivedGifts(recipientId: string, beforeId: string | null, limit: number): Promise<Gift[]> {
    return this.prisma.giftSent.findMany({
      where: { recipientId, ...(beforeId ? { id: { lt: beforeId } } : {}) },
      orderBy: { id: 'desc' },
      take: limit,
      select: giftSelect,
    });
  }

  listGifts(filter: { userId?: string }, beforeId: string | null, limit: number): Promise<Gift[]> {
    return this.prisma.giftSent.findMany({
      where: {
        ...(filter.userId ? { OR: [{ senderId: filter.userId }, { recipientId: filter.userId }] } : {}),
        ...(beforeId ? { id: { lt: beforeId } } : {}),
      },
      orderBy: { id: 'desc' },
      take: limit,
      select: giftSelect,
    });
  }
}

const giftSelect = {
  id: true,
  senderId: true,
  recipientId: true,
  videoId: true,
  giftCode: true,
  amount: true,
  senderBalanceAfter: true,
  createdAt: true,
} as const;
