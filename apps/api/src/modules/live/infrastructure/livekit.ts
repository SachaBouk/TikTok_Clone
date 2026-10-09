import { Injectable, Logger } from '@nestjs/common';
import type { LiveRoomEvent } from '@repo/shared';
import { LIVE_ROOM_TOPIC } from '@repo/shared';
import { AccessToken, DataPacket_Kind, RoomServiceClient, WebhookReceiver } from 'livekit-server-sdk';
import type { User } from '../../users/domain/user';
import { toUserSummary } from '../../users/interfaces/user-summary.response';
import { giftDisplay } from '../../wallet/domain/gift-catalog';
import type { LiveEndReason, LiveMessage } from '../domain/live';
import type { GiftDetails } from '../domain/live-events';
import { LiveMedia, type LiveMediaEvent, LiveRoomPublisher } from '../domain/live-media';
import { toLiveChatMessageDto } from '../interfaces/live.responses';
import { LiveKitConfig } from './live.config';

// Adaptateurs LiveKit (ADR-053), par le SDK serveur officiel : salles (API REST du serveur), jetons d'accès (JWT signés
// par la clé), messages de données (événements de la salle), webhook (signé par la même clé).

// Salle sans participant fermée par le serveur au bout de ce délai (l'API la ferme d'abord à la fin du live).
const EMPTY_ROOM_TIMEOUT_SECONDS = 5 * 60;

@Injectable()
export class LiveKitMedia extends LiveMedia {
  private readonly rooms: RoomServiceClient;
  private readonly receiver: WebhookReceiver;

  constructor(private readonly config: LiveKitConfig) {
    super();
    this.rooms = new RoomServiceClient(config.apiUrl, config.apiKey, config.apiSecret);
    this.receiver = new WebhookReceiver(config.apiKey, config.apiSecret);
  }

  get publicUrl(): string {
    return this.config.publicUrl;
  }

  async createRoom(liveId: string): Promise<void> {
    await this.rooms.createRoom({ name: liveId, emptyTimeout: EMPTY_ROOM_TIMEOUT_SECONDS });
  }

  async deleteRoom(liveId: string): Promise<void> {
    try {
      await this.rooms.deleteRoom(liveId);
    } catch (error) {
      if (!isNotFound(error)) throw error;
    }
  }

  async listRooms(): Promise<string[]> {
    return (await this.rooms.listRooms()).map((room) => room.name);
  }

  async isConnected(liveId: string, identity: string): Promise<boolean> {
    try {
      await this.rooms.getParticipant(liveId, identity);
      return true;
    } catch (error) {
      if (isNotFound(error)) return false;
      throw error;
    }
  }

  async createToken(grant: { liveId: string; identity: string; name: string; canPublish: boolean; ttlSeconds: number }): Promise<string> {
    const token = new AccessToken(this.config.apiKey, this.config.apiSecret, { identity: grant.identity, name: grant.name, ttl: grant.ttlSeconds });
    // Ni salle créée par un jeton (elle est ouverte par l'API), ni données envoyées par l'app : chat, cœurs et cadeaux
    // passent par l'API.
    token.addGrant({
      room: grant.liveId,
      roomJoin: true,
      roomCreate: false,
      canPublish: grant.canPublish,
      canSubscribe: true,
      canPublishData: false,
    });
    return token.toJwt();
  }

  // JWT signé par la clé du serveur, avec l'empreinte du corps.
  async receiveWebhook(body: string, authorization: string | undefined): Promise<LiveMediaEvent | null> {
    const event = await this.receiver.receive(body, authorization);
    const liveId = event.room?.name;
    if (!liveId) return null;
    switch (event.event) {
      case 'participant_joined':
        return event.participant
          ? { type: 'participantJoined', liveId, identity: event.participant.identity, participantsCount: event.room?.numParticipants ?? 0 }
          : null;
      case 'participant_left':
        return event.participant ? { type: 'participantLeft', liveId, identity: event.participant.identity } : null;
      case 'room_finished':
        return { type: 'roomFinished', liveId };
      default:
        return null;
    }
  }

  // Message de données fiable, sujet `live`, à tous les participants de la salle.
  async send(liveId: string, event: LiveRoomEvent): Promise<void> {
    await this.rooms.sendData(liveId, new TextEncoder().encode(JSON.stringify(event)), DataPacket_Kind.RELIABLE, { topic: LIVE_ROOM_TOPIC });
  }
}

// Événements de la salle, au format du contrat (`LiveRoomEvent`, publié dans la spec OpenAPI pour l'app).
@Injectable()
export class LiveKitRoomPublisher extends LiveRoomPublisher {
  private readonly logger = new Logger('LiveRoom');

  constructor(private readonly media: LiveKitMedia) {
    super();
  }

  chatMessage(message: LiveMessage, author: User): Promise<void> {
    return this.send(message.liveId, { event: 'chatMessage', data: toLiveChatMessageDto(message, author) });
  }

  chatMessageDeleted(liveId: string, messageId: string): Promise<void> {
    return this.send(liveId, { event: 'chatMessageDeleted', data: { messageId } });
  }

  hearts(liveId: string, count: number, total: number): Promise<void> {
    return this.send(liveId, { event: 'hearts', data: { count, total } });
  }

  gift(liveId: string, sender: User, gift: GiftDetails, totals: { giftsCount: number; giftsAmount: number }): Promise<void> {
    const display = giftDisplay(gift.code);
    return this.send(liveId, {
      event: 'gift',
      data: {
        sender: toUserSummary(sender),
        gift: { code: gift.code, name: display.name, emoji: display.emoji },
        amount: gift.amount,
        giftsCount: totals.giftsCount,
        giftsAmount: totals.giftsAmount,
      },
    });
  }

  liveEnded(liveId: string, reason: LiveEndReason): Promise<void> {
    return this.send(liveId, { event: 'liveEnded', data: { reason } });
  }

  private async send(liveId: string, event: LiveRoomEvent): Promise<void> {
    try {
      await this.media.send(liveId, event);
    } catch (error) {
      // Au mieux : salle déjà fermée, serveur indisponible. L'erreur est journalisée, jamais propagée à la requête.
      this.logger.warn(`Événement ${event.event} non diffusé dans la salle ${liveId} : ${(error as Error).message}`);
    }
  }
}

// Réponse « introuvable » de l'API du serveur (Twirp : code `not_found`, statut HTTP 404).
function isNotFound(error: unknown): boolean {
  const candidate = error as { status?: number; code?: string } | undefined;
  return candidate?.status === 404 || candidate?.code === 'not_found';
}
