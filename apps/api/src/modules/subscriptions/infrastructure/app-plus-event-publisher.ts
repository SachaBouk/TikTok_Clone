import { Injectable } from '@nestjs/common';
import { RealtimeService } from '../../realtime/application/realtime.service';
import { PlusEventPublisher } from '../domain/plus-events';
import type { PlusStatus } from '../domain/plus-subscription';
import { toPlusStatusDto } from '../interfaces/subscriptions.responses';

// État de l'abonnement envoyé par WebSocket (module realtime, ADR-011) à tous les appareils du compte.
@Injectable()
export class AppPlusEventPublisher extends PlusEventPublisher {
  constructor(private readonly realtime: RealtimeService) {
    super();
  }

  async plusChanged(userId: string, status: PlusStatus): Promise<void> {
    await this.realtime.sendToUser(userId, { event: 'plusChanged', data: toPlusStatusDto(status) });
  }
}
