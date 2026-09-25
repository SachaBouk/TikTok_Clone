import { ApiProperty } from '@nestjs/swagger';
import type {
  ConversationAcceptedEventDto,
  ConversationDeletedEventDto,
  ConversationReadEventDto,
  MessageCreatedEventDto,
  MessageDeletedEventDto,
  TypingClientMessageDto,
  TypingEventDto,
} from '@repo/shared';
import { MessageResponse } from './messaging.responses';

// Schémas OpenAPI des événements WebSocket (ADR-011), rattachés aux unions `RealtimeEvent` (serveur → app)
// et `RealtimeClientMessage` (app → serveur) dans src/openapi. Chaque événement de messagerie porte les
// badges de son destinataire.

class MessagingBadgesData {
  @ApiProperty({ type: 'integer', minimum: 0, description: 'Conversations (hors demandes) ayant au moins un message non lu.' })
  unreadConversations!: number;

  @ApiProperty({ type: 'integer', minimum: 0, description: 'Demandes reçues en attente.' })
  pendingRequests!: number;
}

export class MessageCreatedData extends MessagingBadgesData {
  @ApiProperty({ type: MessageResponse })
  message!: MessageResponse;
}

export class MessageCreatedEvent implements MessageCreatedEventDto {
  @ApiProperty({ enum: ['messageCreated'] })
  event!: 'messageCreated';

  @ApiProperty({ type: MessageCreatedData })
  data!: MessageCreatedData;
}

export class MessageDeletedData extends MessagingBadgesData {
  @ApiProperty({ format: 'uuid' })
  conversationId!: string;
  @ApiProperty({ format: 'uuid', description: 'Message retiré.' })
  messageId!: string;
}

export class MessageDeletedEvent implements MessageDeletedEventDto {
  @ApiProperty({ enum: ['messageDeleted'] })
  event!: 'messageDeleted';

  @ApiProperty({ type: MessageDeletedData })
  data!: MessageDeletedData;
}

export class ConversationReadData extends MessagingBadgesData {
  @ApiProperty({ format: 'uuid' })
  conversationId!: string;
  @ApiProperty({ format: 'uuid', description: 'Participant qui a lu.' })
  readerId!: string;
  @ApiProperty({ format: 'uuid', description: 'Lu jusqu’à ce message inclus.' })
  lastReadMessageId!: string;
}

export class ConversationReadEvent implements ConversationReadEventDto {
  @ApiProperty({ enum: ['conversationRead'] })
  event!: 'conversationRead';

  @ApiProperty({ type: ConversationReadData })
  data!: ConversationReadData;
}

export class ConversationAcceptedData extends MessagingBadgesData {
  @ApiProperty({ format: 'uuid' })
  conversationId!: string;
}

export class ConversationAcceptedEvent implements ConversationAcceptedEventDto {
  @ApiProperty({ enum: ['conversationAccepted'] })
  event!: 'conversationAccepted';

  @ApiProperty({ type: ConversationAcceptedData })
  data!: ConversationAcceptedData;
}

export class ConversationDeletedData extends MessagingBadgesData {
  @ApiProperty({ format: 'uuid' })
  conversationId!: string;
}

export class ConversationDeletedEvent implements ConversationDeletedEventDto {
  @ApiProperty({ enum: ['conversationDeleted'] })
  event!: 'conversationDeleted';

  @ApiProperty({ type: ConversationDeletedData })
  data!: ConversationDeletedData;
}

export class TypingData {
  @ApiProperty({ format: 'uuid' })
  conversationId!: string;

  @ApiProperty({ format: 'uuid', description: 'Participant en train d’écrire.' })
  userId!: string;
}

// À afficher quelques secondes (5 s conseillées), prolongé par l'événement suivant.
export class TypingEvent implements TypingEventDto {
  @ApiProperty({ enum: ['typing'] })
  event!: 'typing';

  @ApiProperty({ type: TypingData })
  data!: TypingData;
}

export class TypingClientData {
  @ApiProperty({ format: 'uuid' })
  conversationId!: string;
}

// Envoyé par l'app toutes les ~3 s pendant la saisie.
export class TypingClientMessage implements TypingClientMessageDto {
  @ApiProperty({ enum: ['typing'] })
  event!: 'typing';

  @ApiProperty({ type: TypingClientData })
  data!: TypingClientData;
}
