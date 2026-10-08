import { Injectable } from '@nestjs/common';
import type { MessagingBadgesDto } from '@repo/shared';
import { PushService } from '../../push/application/push.service';
import { PUSH_BODY_MAX_LENGTH } from '../../push/domain/push';
import { RealtimeService } from '../../realtime/application/realtime.service';
import type { User } from '../../users/domain/user';
import type { MessageItem, MessagingBadges } from '../domain/messaging';
import { MessagingEventPublisher } from '../domain/messaging-event-publisher';
import { toMessageDto } from '../interfaces/messaging.responses';

// Prévient les appareils d'un participant : WebSocket (module realtime, ADR-011), au même format que l'API
// REST, et notification push (module push) pour un nouveau message ou une nouvelle demande.
@Injectable()
export class AppMessagingEventPublisher extends MessagingEventPublisher {
  constructor(
    private readonly realtime: RealtimeService,
    private readonly push: PushService,
  ) {
    super();
  }

  messageCreated(recipientId: string, item: MessageItem, badges: MessagingBadges): Promise<void> {
    return this.realtime.sendToUser(recipientId, { event: 'messageCreated', data: { message: toMessageDto(item), ...toBadges(badges) } });
  }

  messageDeleted(recipientId: string, message: { conversationId: string; messageId: string }, badges: MessagingBadges): Promise<void> {
    return this.realtime.sendToUser(recipientId, { event: 'messageDeleted', data: { ...message, ...toBadges(badges) } });
  }

  conversationRead(
    recipientId: string,
    read: { conversationId: string; readerId: string; lastReadMessageId: string },
    badges: MessagingBadges,
  ): Promise<void> {
    return this.realtime.sendToUser(recipientId, { event: 'conversationRead', data: { ...read, ...toBadges(badges) } });
  }

  conversationAccepted(recipientId: string, conversationId: string, badges: MessagingBadges): Promise<void> {
    return this.realtime.sendToUser(recipientId, { event: 'conversationAccepted', data: { conversationId, ...toBadges(badges) } });
  }

  conversationDeleted(recipientId: string, conversationId: string, badges: MessagingBadges): Promise<void> {
    return this.realtime.sendToUser(recipientId, { event: 'conversationDeleted', data: { conversationId, ...toBadges(badges) } });
  }

  typing(recipientId: string, typing: { conversationId: string; userId: string }): Promise<void> {
    return this.realtime.sendToUser(recipientId, { event: 'typing', data: typing });
  }

  pushNewMessage(recipientId: string, sender: User, { message }: MessageItem, asRequest: boolean): Promise<void> {
    const text = message.storyId ? `Réponse à ta story : ${message.content}` : message.content || 'a partagé une vidéo';
    return this.push.notify(recipientId, {
      title: asRequest ? 'Demande de message' : sender.displayName,
      body: (asRequest ? `${sender.displayName} : ${text}` : text).slice(0, PUSH_BODY_MAX_LENGTH),
      threadId: `conversation:${message.conversationId}`,
      data: { type: asRequest ? 'messageRequest' : 'message', conversationId: message.conversationId, messageId: message.id },
    });
  }
}

// Mapping explicite des badges (noms identiques, mais rien n'est exposé par accident).
function toBadges(badges: MessagingBadges): MessagingBadgesDto {
  return { unreadConversations: badges.unreadConversations, pendingRequests: badges.pendingRequests };
}
