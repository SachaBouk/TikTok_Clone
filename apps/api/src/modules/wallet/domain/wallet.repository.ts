import type { Gift, NewGift, SendGiftResult, WalletAmounts } from './gift';
import type { ApplyResult, LedgerFilter, NewWalletEntry, WalletLedgerEntry, WalletStats, WalletTransaction } from './wallet';

// Port des tables wallets et wallet_transactions (ADR-006, ADR-009).
export abstract class WalletRepository {
  // 0 pour un compte sans portefeuille (créé au premier mouvement).
  abstract getBalance(userId: string): Promise<number>;
  // Solde et gains (ADR-050) ; 0 et 0 sans portefeuille.
  abstract getAmounts(userId: string): Promise<WalletAmounts>;
  // Enregistre le mouvement et met à jour le solde, de façon atomique et idempotente : un événement déjà
  // enregistré (même `eventId`) n'est pas réappliqué. Le mouvement appliqué suit `appliedAmount`.
  abstract apply(entry: NewWalletEntry): Promise<ApplyResult>;
  // Mouvements du compte, du plus récent au plus ancien (identifiants UUID v7), strictement avant `beforeId`.
  abstract listTransactions(userId: string, beforeId: string | null, limit: number): Promise<WalletTransaction[]>;

  // Backoffice (ADR-004) : soldes de ces comptes (absents : 0).
  abstract getBalances(userIds: string[]): Promise<Map<string, number>>;
  // Backoffice : journal complet, filtré, du plus récent au plus ancien, strictement avant `beforeId`.
  abstract listLedger(filter: LedgerFilter, beforeId: string | null, limit: number): Promise<WalletLedgerEntry[]>;
  // Backoffice : totaux des jetons, achats en production et cadeaux depuis `since`.
  abstract getStats(since: Date): Promise<WalletStats>;
  // Backoffice : gains de ces comptes (absents : 0).
  abstract getEarnings(userIds: string[]): Promise<Map<string, number>>;

  // Cadeaux (ADR-050). Débite l'expéditeur et crédite les gains du destinataire, dans une transaction : les deux
  // portefeuilles sont verrouillés dans l'ordre des identifiants (pas d'interblocage entre cadeaux croisés).
  // Idempotent par (expéditeur, identifiant d'envoi) : un renvoi rend le cadeau existant, sans nouveau débit.
  abstract sendGift(gift: NewGift): Promise<SendGiftResult>;
  // Cadeau déjà envoyé avec cet identifiant d'envoi.
  abstract findGiftByClientId(senderId: string, clientGiftId: string): Promise<Gift | null>;
  // Du plus récent au plus ancien (identifiants UUID v7), strictement avant `beforeId`.
  abstract listSentGifts(senderId: string, beforeId: string | null, limit: number): Promise<Gift[]>;
  abstract listReceivedGifts(recipientId: string, beforeId: string | null, limit: number): Promise<Gift[]>;
  // Backoffice : tous les cadeaux, ou ceux envoyés ou reçus par `userId`.
  abstract listGifts(filter: { userId?: string }, beforeId: string | null, limit: number): Promise<Gift[]>;
}
