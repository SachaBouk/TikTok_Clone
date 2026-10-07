// Cadeaux en jetons (ADR-050) : débités du solde de l'expéditeur, crédités aux gains (`earned`) du destinataire, qui ne
// se dépensent pas. Un cadeau envoyé est définitif.

export interface Gift {
  id: string;
  // Nuls : compte supprimé depuis (ligne gardée, anonymisée).
  senderId: string | null;
  recipientId: string | null;
  // Nulle : vidéo supprimée depuis.
  videoId: string | null;
  giftCode: string;
  // Prix payé, en jetons.
  amount: number;
  senderBalanceAfter: number;
  createdAt: Date;
}

export interface NewGift {
  senderId: string;
  recipientId: string;
  videoId: string;
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
