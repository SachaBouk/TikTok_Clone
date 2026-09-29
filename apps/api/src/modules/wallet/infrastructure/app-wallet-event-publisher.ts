import { Injectable } from '@nestjs/common';
import { RealtimeService } from '../../realtime/application/realtime.service';
import { WalletEventPublisher } from '../domain/wallet-events';

// Solde à jour envoyé par WebSocket (module realtime, ADR-011) à tous les appareils du compte.
@Injectable()
export class AppWalletEventPublisher extends WalletEventPublisher {
  constructor(private readonly realtime: RealtimeService) {
    super();
  }

  async balanceChanged(userId: string, balance: number): Promise<void> {
    await this.realtime.sendToUser(userId, { event: 'walletUpdated', data: { balance } });
  }
}
