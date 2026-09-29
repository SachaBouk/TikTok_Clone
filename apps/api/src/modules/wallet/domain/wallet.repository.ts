import type { ApplyResult, NewWalletEntry, WalletTransaction } from './wallet';

// Port des tables wallets et wallet_transactions (ADR-006, ADR-009).
export abstract class WalletRepository {
  // 0 pour un compte sans portefeuille (créé au premier mouvement).
  abstract getBalance(userId: string): Promise<number>;
  // Enregistre le mouvement et met à jour le solde, de façon atomique et idempotente : un événement déjà
  // enregistré (même `eventId`) n'est pas réappliqué. Le mouvement appliqué suit `appliedAmount`.
  abstract apply(entry: NewWalletEntry): Promise<ApplyResult>;
  // Mouvements du compte, du plus récent au plus ancien (identifiants UUID v7), strictement avant `beforeId`.
  abstract listTransactions(userId: string, beforeId: string | null, limit: number): Promise<WalletTransaction[]>;
}
