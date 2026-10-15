import type { User } from '../../users/domain/user';
import type { MessageItem, MessagingBadges } from './messaging';

// Événements vers les appareils d'un participant : WebSocket (ADR-011), et notification push pour un
// nouveau message. Au mieux : sans connexion, ils sont perdus, et l'app relit l'état par l'API REST.
export abstract class MessagingEventPublisher {
  abstract messageCreated(recipientId: string, item: MessageItem, badges: MessagingBadges): Promise<void>;
  abstract messageDeleted(recipientId: string, message: { conversationId: string; messageId: string }, badges: MessagingBadges): Promise<void>;
  abstract conversationRead(
    recipientId: string,
    read: { conversationId: string; readerId: string; lastReadMessageId: string },
    badges: MessagingBadges,
  ): Promise<void>;
  // Demande acceptée : la conversation devient libre pour les deux.
  abstract conversationAccepted(recipientId: string, conversationId: string, badges: MessagingBadges): Promise<void>;
  // Conversation supprimée (ou demande refusée) pour ce compte : ses autres appareils la retirent.
  abstract conversationDeleted(recipientId: string, conversationId: string, badges: MessagingBadges): Promise<void>;
  abstract typing(recipientId: string, typing: { conversationId: string; userId: string }): Promise<void>;
  // Notification push d'un nouveau message (ou d'une nouvelle demande) au destinataire.
  abstract pushNewMessage(recipientId: string, sender: User, item: MessageItem, asRequest: boolean): Promise<void>;
  // Notification push d'un message de groupe (ADR-059) : titre = nom du groupe (ou noms des membres).
  abstract pushGroupMessage(recipientId: string, sender: User, groupTitle: string, item: MessageItem): Promise<void>;
}
