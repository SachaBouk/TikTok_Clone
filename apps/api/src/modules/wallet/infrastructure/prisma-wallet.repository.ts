import { Injectable } from '@nestjs/common';
import { violatedUniqueConstraint } from '../../../database/prisma-errors';
import { PrismaService } from '../../../database/prisma.service';
import { appliedAmount, type ApplyResult, type NewWalletEntry, type WalletTransaction } from '../domain/wallet';
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
        if (entry.userId) {
          await tx.wallet.createMany({ data: [{ userId: entry.userId }], skipDuplicates: true });
          const [wallet] = await tx.$queryRaw<{ balance: number }[]>`SELECT balance FROM wallets WHERE user_id = ${entry.userId}::uuid FOR UPDATE`;
          applied = appliedAmount(wallet!.balance, entry.amount);
          balance = wallet!.balance + applied;
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
        return { status: 'applied' as const, appliedAmount: applied, balance };
      });
    } catch (error) {
      if (violatedUniqueConstraint(error)?.includes('revenuecat_event_id')) return { status: 'duplicate' };
      throw error;
    }
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
}
