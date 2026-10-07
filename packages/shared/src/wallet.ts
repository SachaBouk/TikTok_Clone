import type { UserSummaryDto } from './users.js';

// Portefeuille de jetons (ADR-009) : achats validés par RevenueCat, solde tenu par l'API. Cadeaux (ADR-050).

export interface WalletDto {
  // Jetons disponibles (achetés), seuls dépensables.
  balance: number;
  // Jetons reçus en cadeaux (ADR-050) : gains à part, ni dépensables ni retirables.
  earned: number;
}

// Nature d'un mouvement du solde : achat d'un pack, remboursement par le store, ajustement manuel (tableau
// de bord RevenueCat), cadeau envoyé (ADR-050).
export type WalletTransactionKind = 'purchase' | 'refund' | 'adjustment' | 'giftSent';

// Cadeau du catalogue (ADR-050) : code, nom et emoji (« 🎁 Cadeau » pour un code retiré depuis).
export interface GiftDto {
  code: string;
  name: string;
  emoji: string;
}

export interface GiftCatalogItemDto extends GiftDto {
  // Prix en jetons.
  price: number;
}

export interface GiftCatalogDto {
  // Du moins cher au plus cher.
  items: GiftCatalogItemDto[];
}

// Cadeau d'un mouvement `giftSent` : cadeau et destinataire (absent : compte supprimé depuis).
export interface WalletTransactionGiftDto extends GiftDto {
  recipient?: UserSummaryDto;
}

// Cadeau envoyé (`POST /videos/:id/gifts`).
export interface SentGiftDto {
  id: string;
  gift: GiftDto;
  // Prix payé.
  amount: number;
  // Solde de l'expéditeur après le débit.
  balance: number;
  createdAt: string;
}

// Vidéo d'un cadeau reçu (absente si elle n'est plus publiée).
export interface GiftVideoDto {
  id: string;
  thumbnailUrl: string;
}

// Cadeau reçu (`GET /wallet/gifts/received`).
export interface ReceivedGiftDto {
  id: string;
  gift: GiftDto;
  amount: number;
  // Absent : compte supprimé depuis.
  sender?: UserSummaryDto;
  video?: GiftVideoDto;
  createdAt: string;
}

export interface ReceivedGiftPageDto {
  // Du plus récent au plus ancien.
  items: ReceivedGiftDto[];
  nextCursor: string | null;
}

export interface WalletTransactionDto {
  id: string;
  kind: WalletTransactionKind;
  // Variation réelle du solde : positive pour un crédit, négative pour un retrait.
  amount: number;
  // Solde juste après ce mouvement.
  balanceAfter: number;
  // Produit acheté (pack de jetons), s'il y en a un.
  productId: string | null;
  // Cadeau envoyé (sorte `giftSent`) seulement.
  gift?: WalletTransactionGiftDto;
  createdAt: string;
}

export interface WalletTransactionPageDto {
  // Du mouvement le plus récent au plus ancien.
  items: WalletTransactionDto[];
  nextCursor: string | null;
}
