// Portefeuille de jetons (ADR-009). RevenueCat valide les achats auprès du store et tient sa propre monnaie
// virtuelle ; l'API reste la source de vérité du solde : elle applique chaque mouvement annoncé par webhook,
// une seule fois, dans son journal (`wallet_transactions`).

export type WalletTransactionKind = 'purchase' | 'refund' | 'adjustment';

// Un mouvement du journal, tel qu'il a été appliqué au solde du compte.
export interface WalletTransaction {
  id: string;
  kind: WalletTransactionKind;
  // Variation réelle du solde (le mouvement appliqué).
  amount: number;
  balanceAfter: number;
  productId: string | null;
  occurredAt: Date;
}

// Mouvement de la monnaie des jetons annoncé par RevenueCat (événement VIRTUAL_CURRENCY_TRANSACTION).
export interface CurrencyEvent {
  // Identifiant de l'événement : le même à chaque renvoi du webhook.
  eventId: string;
  // Identifiants du client chez RevenueCat, du plus récent au plus ancien : app_user_id, original_app_user_id, alias.
  // L'app s'identifie avec l'UUID du compte (`Purchases.logIn`).
  appUserIds: string[];
  // Somme des ajustements dans la monnaie des jetons : positive pour un achat, négative pour un remboursement.
  amount: number;
  // `in_app_purchase` (achat, remboursement) ou `admin_api` (ajustement depuis le tableau de bord RevenueCat).
  source: string;
  productId: string | null;
  storeTransactionId: string | null;
  store: string | null;
  // SANDBOX (Xcode, TestFlight, Test Store) ou PRODUCTION.
  environment: string;
  occurredAt: Date;
}

export interface NewWalletEntry {
  eventId: string;
  // Nul : aucun compte de l'API ne correspond au client RevenueCat (mouvement gardé pour rapprochement).
  userId: string | null;
  kind: WalletTransactionKind;
  amount: number;
  appUserId: string;
  productId: string | null;
  storeTransactionId: string | null;
  store: string | null;
  environment: string;
  occurredAt: Date;
}

export type ApplyResult =
  | { status: 'applied'; appliedAmount: number; balance: number | null }
  // Événement déjà appliqué (webhook rejoué).
  | { status: 'duplicate' };

// Un retrait (remboursement) ne fait jamais passer le solde sous 0, comme chez RevenueCat : si les jetons ont
// déjà été dépensés, seul le reste est retiré.
export function appliedAmount(balance: number, amount: number): number {
  return Math.max(amount, -balance);
}

export const DEFAULT_TRANSACTIONS_PAGE_SIZE = 20;
export const MAX_TRANSACTIONS_PAGE_SIZE = 50;
