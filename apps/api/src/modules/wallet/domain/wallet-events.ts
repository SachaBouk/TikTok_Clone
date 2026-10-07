import type { WalletAmounts } from './gift';

// Événements du module vers les appareils du compte (ADR-011) : le solde affiché suit sans relecture.
// Au mieux : sans connexion, l'app relit `GET /wallet`.
export abstract class WalletEventPublisher {
  // Solde et gains à jour (ADR-050 : un cadeau change le solde de l'expéditeur et les gains du destinataire).
  abstract balanceChanged(userId: string, amounts: WalletAmounts): Promise<void>;
}
