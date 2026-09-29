import { WalletEventPublisher } from '../domain/wallet-events';

// Adaptateur en mémoire pour les tests : garde les soldes publiés.
export class InMemoryWalletEventPublisher extends WalletEventPublisher {
  readonly published: { userId: string; balance: number }[] = [];

  async balanceChanged(userId: string, balance: number): Promise<void> {
    this.published.push({ userId, balance });
  }
}
