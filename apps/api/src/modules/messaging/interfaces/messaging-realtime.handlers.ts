import { Injectable, OnModuleInit } from '@nestjs/common';
import { RealtimeService } from '../../realtime/application/realtime.service';
import { MessagingService } from '../application/messaging.service';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Messages WebSocket de l'app pour la messagerie (ADR-011), point d'entrée au même titre qu'un controller.
// Enregistrés auprès de RealtimeService : le module realtime ne dépend pas de messaging (pas de cycle).
@Injectable()
export class MessagingRealtimeHandlers implements OnModuleInit {
  constructor(
    private readonly realtime: RealtimeService,
    private readonly messaging: MessagingService,
  ) {}

  onModuleInit() {
    // { "event": "typing", "data": { "conversationId": "…" } } : relayé à l'autre participant s'il y a lieu.
    this.realtime.onClientMessage('typing', async (userId, data) => {
      const conversationId = (data as { conversationId?: unknown } | null)?.conversationId;
      if (typeof conversationId === 'string' && UUID.test(conversationId)) await this.messaging.typing(userId, conversationId);
    });
  }
}
