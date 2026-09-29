import type { MessageDto } from './messaging.js';
import type { NotificationDto } from './notifications.js';
import type { VideoDto } from './videos.js';
import type { WalletDto } from './wallet.js';

// Messages du WebSocket `/realtime` (ADR-011), surtout du serveur vers l'app (voir aussi RealtimeClientMessageDto).
// Forme `{ event, data }` ; `event` distingue les types (discriminant du schéma OpenAPI `RealtimeEvent`).
// Rien n'est rejoué après une déconnexion : à la reconnexion, l'app relit l'état par l'API REST.

// Fin du transcodage d'une vidéo, envoyé à son auteur (ADR-008) : `status` vaut `ready` ou `failed`.
export interface VideoProcessedEventDto {
  event: 'videoProcessed';
  data: VideoDto;
}

// Nouvelle notification dans le centre d'activité, avec le badge à jour.
export interface NotificationCreatedEventDto {
  event: 'notificationCreated';
  data: { notification: NotificationDto; unreadCount: number };
}

// Badge changé sans nouvelle notification : marquage lu (sur cet appareil ou un autre), notification retirée.
export interface UnreadNotificationsChangedEventDto {
  event: 'unreadNotificationsChanged';
  data: { unreadCount: number };
}

// Badges de la messagerie du destinataire de l'événement, joints à chaque événement de messagerie.
export interface MessagingBadgesDto {
  // Conversations (hors demandes) ayant au moins un message non lu.
  unreadConversations: number;
  // Demandes reçues en attente.
  pendingRequests: number;
}

// Nouveau message, envoyé à tous les participants (y compris les autres appareils de l'expéditeur).
export interface MessageCreatedEventDto {
  event: 'messageCreated';
  data: MessagingBadgesDto & { message: MessageDto };
}

// Message retiré par son expéditeur.
export interface MessageDeletedEventDto {
  event: 'messageDeleted';
  data: MessagingBadgesDto & { conversationId: string; messageId: string };
}

// Un participant a lu la conversation jusqu'à `lastReadMessageId` : « Vu » chez l'autre (conversation acceptée
// seulement), badges à jour chez lui.
export interface ConversationReadEventDto {
  event: 'conversationRead';
  data: MessagingBadgesDto & { conversationId: string; readerId: string; lastReadMessageId: string };
}

// Demande acceptée : la conversation devient libre pour les deux participants.
export interface ConversationAcceptedEventDto {
  event: 'conversationAccepted';
  data: MessagingBadgesDto & { conversationId: string };
}

// Conversation supprimée (ou demande refusée) pour ce compte, depuis l'un de ses appareils.
export interface ConversationDeletedEventDto {
  event: 'conversationDeleted';
  data: MessagingBadgesDto & { conversationId: string };
}

// L'autre participant est en train d'écrire : à afficher quelques secondes, prolongé par l'événement suivant.
export interface TypingEventDto {
  event: 'typing';
  data: { conversationId: string; userId: string };
}

// Solde de jetons changé (achat crédité, remboursement), envoyé à tous les appareils du compte (ADR-009).
export interface WalletUpdatedEventDto {
  event: 'walletUpdated';
  data: WalletDto;
}

export type RealtimeEventDto =
  | VideoProcessedEventDto
  | NotificationCreatedEventDto
  | UnreadNotificationsChangedEventDto
  | MessageCreatedEventDto
  | MessageDeletedEventDto
  | ConversationReadEventDto
  | ConversationAcceptedEventDto
  | ConversationDeletedEventDto
  | TypingEventDto
  | WalletUpdatedEventDto;

// Messages de l'app vers le serveur, sur le même WebSocket. Les autres sont ignorés.
// `typing` : à envoyer toutes les ~3 s pendant la saisie dans une conversation.
export interface TypingClientMessageDto {
  event: 'typing';
  data: { conversationId: string };
}

export type RealtimeClientMessageDto = TypingClientMessageDto;
