// Cadeaux en jetons (ADR-050) : débités du solde de l'expéditeur, crédités aux gains (`earned`) du destinataire, qui ne
// se dépensent pas. Un cadeau envoyé est définitif.

export interface Gift {
  id: string;
  // Nuls : compte supprimé depuis (ligne gardée, anonymisée).
  senderId: string | null;
  recipientId: string | null;
  // Nulle : vidéo supprimée depuis, ou cadeau envoyé pendant un live.
  videoId: string | null;
  // Live pendant lequel le cadeau a été envoyé (ADR-053) ; nul sur une vidéo.
  liveId: string | null;
  giftCode: string;
  // Prix payé, en jetons.
  amount: number;
  senderBalanceAfter: number;
  createdAt: Date;
}

export interface NewGift {
  senderId: string;
  recipientId: string;
  // L'un ou l'autre : une vidéo, ou un live (ADR-053).
  videoId: string | null;
  liveId: string | null;
  giftCode: string;
  amount: number;
  clientGiftId: string;
}

export type SendGiftResult =
  | { status: 'sent'; gift: Gift; senderBalance: number; recipientEarned: number }
  // Même identifiant d'envoi déjà utilisé par l'expéditeur (renvoi) : le cadeau existant, sans nouveau débit.
  | { status: 'duplicate'; gift: Gift }
  | { status: 'insufficientBalance'; balance: number };

// Solde (jetons achetés, dépensables) et gains (jetons reçus en cadeaux).
export interface WalletAmounts {
  balance: number;
  earned: number;
}
