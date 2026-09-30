import type { ApplyResult, LedgerFilter, NewWalletEntry, WalletLedgerEntry, WalletStats, WalletTransaction } from './wallet';

// Port des tables wallets et wallet_transactions (ADR-006, ADR-009).
export abstract class WalletRepository {
  // 0 pour un compte sans portefeuille (créé au premier mouvement).
  abstract getBalance(userId: string): Promise<number>;
  // Enregistre le mouvement et met à jour le solde, de façon atomique et idempotente : un événement déjà
  // enregistré (même `eventId`) n'est pas réappliqué. Le mouvement appliqué suit `appliedAmount`.
  abstract apply(entry: NewWalletEntry): Promise<ApplyResult>;
  // Mouvements du compte, du plus récent au plus ancien (identifiants UUID v7), strictement avant `beforeId`.
  abstract listTransactions(userId: string, beforeId: string | null, limit: number): Promise<WalletTransaction[]>;

  // Backoffice (ADR-004) : soldes de ces comptes (absents : 0).
  abstract getBalances(userIds: string[]): Promise<Map<string, number>>;
  // Backoffice : journal complet, filtré, du plus récent au plus ancien, strictement avant `beforeId`.
  abstract listLedger(filter: LedgerFilter, beforeId: string | null, limit: number): Promise<WalletLedgerEntry[]>;
  // Backoffice : totaux des jetons, achats en production depuis `since`.
  abstract getStats(since: Date): Promise<WalletStats>;
}
