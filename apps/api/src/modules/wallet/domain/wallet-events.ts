// Événements du module vers les appareils du compte (ADR-011) : le solde affiché suit sans relecture.
// Au mieux : sans connexion, l'app relit `GET /wallet`.
export abstract class WalletEventPublisher {
  abstract balanceChanged(userId: string, balance: number): Promise<void>;
}
