import type { WalletAmounts } from '../domain/gift';
import { WalletEventPublisher } from '../domain/wallet-events';

// Adaptateur en mémoire pour les tests : garde les soldes et gains publiés.
export class InMemoryWalletEventPublisher extends WalletEventPublisher {
  readonly published: ({ userId: string } & WalletAmounts)[] = [];

  async balanceChanged(userId: string, amounts: WalletAmounts): Promise<void> {
    this.published.push({ userId, ...amounts });
  }
}
