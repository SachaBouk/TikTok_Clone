// Portefeuille de jetons (ADR-009) : achats validés par RevenueCat, solde tenu par l'API.

export interface WalletDto {
  // Jetons disponibles.
  balance: number;
}

// Nature d'un mouvement du solde : achat d'un pack, remboursement par le store, ajustement manuel (tableau
// de bord RevenueCat). Les cadeaux (dépense) viendront avec les lives (ADR-016).
export type WalletTransactionKind = 'purchase' | 'refund' | 'adjustment';

export interface WalletTransactionDto {
  id: string;
  kind: WalletTransactionKind;
  // Variation réelle du solde : positive pour un crédit, négative pour un retrait.
  amount: number;
  // Solde juste après ce mouvement.
  balanceAfter: number;
  // Produit acheté (pack de jetons), s'il y en a un.
  productId: string | null;
  createdAt: string;
}

export interface WalletTransactionPageDto {
  // Du mouvement le plus récent au plus ancien.
  items: WalletTransactionDto[];
  nextCursor: string | null;
}
