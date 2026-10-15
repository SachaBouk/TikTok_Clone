import type { User } from '../../users/domain/user';
import type { MessageItem, MessagingBadges } from '../domain/messaging';
import { MessagingEventPublisher } from '../domain/messaging-event-publisher';

export interface RecordedEvent {
  recipientId: string;
  event: string;
  // Résumé lisible : texte du message, identifiant…
  detail: string;
  badges?: MessagingBadges;
}

// Adaptateur en mémoire pour les tests : garde les événements publiés et les notifications push, par destinataire.
export class InMemoryMessagingEventPublisher extends MessagingEventPublisher {
  readonly events: RecordedEvent[] = [];
  readonly pushes: { recipientId: string; senderId: string; content: string; asRequest: boolean; groupTitle?: string }[] = [];
  // Messages remis, tels que chaque destinataire les reçoit (vidéo partagée comprise).
  readonly created: { recipientId: string; item: MessageItem }[] = [];

  async messageCreated(recipientId: string, item: MessageItem, badges: MessagingBadges): Promise<void> {
    this.events.push({ recipientId, event: 'messageCreated', detail: item.message.content, badges });
    this.created.push({ recipientId, item });
  }

  async messageDeleted(recipientId: string, message: { conversationId: string; messageId: string }, badges: MessagingBadges): Promise<void> {
    this.events.push({ recipientId, event: 'messageDeleted', detail: message.messageId, badges });
  }

  async conversationRead(
    recipientId: string,
    read: { conversationId: string; readerId: string; lastReadMessageId: string },
    badges: MessagingBadges,
  ): Promise<void> {
    this.events.push({ recipientId, event: 'conversationRead', detail: `${read.readerId}:${read.lastReadMessageId}`, badges });
  }

  async conversationAccepted(recipientId: string, conversationId: string, badges: MessagingBadges): Promise<void> {
    this.events.push({ recipientId, event: 'conversationAccepted', detail: conversationId, badges });
  }

  async conversationDeleted(recipientId: string, conversationId: string, badges: MessagingBadges): Promise<void> {
    this.events.push({ recipientId, event: 'conversationDeleted', detail: conversationId, badges });
  }

  async typing(recipientId: string, typing: { conversationId: string; userId: string }): Promise<void> {
    this.events.push({ recipientId, event: 'typing', detail: typing.userId });
  }

  async pushNewMessage(recipientId: string, sender: User, item: MessageItem, asRequest: boolean): Promise<void> {
    this.pushes.push({ recipientId, senderId: sender.id, content: item.message.content, asRequest });
  }

  async pushGroupMessage(recipientId: string, sender: User, groupTitle: string, item: MessageItem): Promise<void> {
    this.pushes.push({ recipientId, senderId: sender.id, content: item.message.content, asRequest: false, groupTitle });
  }
}
