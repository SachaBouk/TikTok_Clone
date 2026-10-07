// Portefeuille de jetons (ADR-009). RevenueCat valide les achats auprès du store et tient sa propre monnaie
// virtuelle ; l'API reste la source de vérité du solde : elle applique chaque mouvement annoncé par webhook,
// une seule fois, dans son journal (`wallet_transactions`).

export type WalletTransactionKind = 'purchase' | 'refund' | 'adjustment';

// Sortes de l'historique d'un compte, pour la spec (enum nommé partagé par l'app et le backoffice) : celles du journal
// RevenueCat, et les cadeaux envoyés (ADR-050).
export const WALLET_HISTORY_KINDS = ['purchase', 'refund', 'adjustment', 'giftSent'] as const;

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
  // `balance` et `earned` nuls : client inconnu (aucun portefeuille touché).
  | { status: 'applied'; appliedAmount: number; balance: number | null; earned: number | null }
  // Événement déjà appliqué (webhook rejoué).
  | { status: 'duplicate' };

// Un retrait (remboursement) ne fait jamais passer le solde sous 0, comme chez RevenueCat : si les jetons ont
// déjà été dépensés, seul le reste est retiré.
export function appliedAmount(balance: number, amount: number): number {
  return Math.max(amount, -balance);
}

// Backoffice (ADR-004) : une ligne du journal, avec ce qui sert au rapprochement avec RevenueCat et le store.
export interface WalletLedgerEntry {
  id: string;
  // Nul : compte supprimé depuis (ligne anonymisée), ou client inconnu de l'API (`unmatched`).
  userId: string | null;
  kind: WalletTransactionKind;
  // Mouvement annoncé par RevenueCat.
  amount: number;
  // Mouvement réellement appliqué au solde (plancher à 0 ; 0 pour un client inconnu).
  appliedAmount: number;
  balanceAfter: number | null;
  // Client inconnu de l'API au moment du webhook : aucun portefeuille touché, à rapprocher à la main.
  unmatched: boolean;
  revenuecatEventId: string;
  appUserId: string;
  productId: string | null;
  storeTransactionId: string | null;
  store: string | null;
  environment: string;
  occurredAt: Date;
}

// Filtres du journal du backoffice : un compte, ou les seuls mouvements à rapprocher.
export interface LedgerFilter {
  userId?: string;
  unmatched?: boolean;
}

// Jetons annoncés par RevenueCat, par sorte de mouvement (montants positifs), pour un environnement.
export interface TokenTotals {
  // Achats (jetons vendus), clients inconnus compris : le store a encaissé.
  purchased: number;
  refunded: number;
  // Ajustements depuis le tableau de bord RevenueCat (solde net, peut être négatif).
  adjusted: number;
}

// Tableau de bord du backoffice.
export interface WalletStats {
  production: TokenTotals;
  // Achats de test (Xcode, TestFlight, Test Store) : jamais payés.
  sandbox: TokenTotals;
  // Jetons achetés en production depuis `since`.
  purchasedSince: number;
  // Somme des soldes des comptes.
  inCirculation: number;
  // Mouvements de clients inconnus, à rapprocher.
  unmatched: number;
  // Cadeaux (ADR-050) : jetons dépensés (total, et depuis `since`) et gains des comptes existants.
  gifts: GiftTotals;
}

export interface GiftTotals {
  spent: number;
  spentSince: number;
  earned: number;
}

export const PRODUCTION_ENVIRONMENT = 'PRODUCTION';

export const DEFAULT_TRANSACTIONS_PAGE_SIZE = 20;
export const MAX_TRANSACTIONS_PAGE_SIZE = 50;
