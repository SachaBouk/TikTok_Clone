import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import type {
  ConversationDto,
  ConversationPageDto,
  ConversationStatus,
  MessageDto,
  MessagePageDto,
  SharedVideoDto,
  UnreadConversationsDto,
} from '@repo/shared';
import { toUserSummary, UserSummaryResponse } from '../../users/interfaces/user-summary.response';
import type { ConversationWithParticipant } from '../application/messaging.service';
import type { MessageItem, MessagingBadges, SharedVideo } from '../domain/messaging';

// Schémas OpenAPI des DTO partagés : `implements` garantit à la compilation que chaque classe suit son type.
// Objets imbriqués sans description : elle produirait un `allOf`, que le client Swift envelopperait (voir CLAUDE.md).

export class SharedVideoResponse implements SharedVideoDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty({ description: 'Faux si la vidéo a été supprimée depuis le partage : les autres champs sont alors nuls.' })
  available!: boolean;

  @ApiProperty({ type: String, nullable: true, format: 'uri' })
  thumbnailUrl!: string | null;

  @ApiProperty({ type: String, nullable: true, format: 'uri' })
  hlsUrl!: string | null;

  @ApiProperty({ type: String, nullable: true })
  description!: string | null;

  // Absent si la vidéo n'est plus disponible.
  @ApiPropertyOptional({ type: UserSummaryResponse })
  author?: UserSummaryResponse;
}

export class MessageResponse implements MessageDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty({ format: 'uuid' })
  conversationId!: string;

  @ApiProperty({ format: 'uuid' })
  senderId!: string;

  @ApiProperty({ description: 'Vide si le message ne fait que partager une vidéo.' })
  content!: string;

  // Absent si le message ne partage pas de vidéo.
  @ApiPropertyOptional({ type: SharedVideoResponse })
  sharedVideo?: SharedVideoResponse;

  @ApiPropertyOptional({
    format: 'uuid',
    description: 'Identifiant d’envoi choisi par l’app (ADR-044) : seulement dans la réponse à l’envoi et l’écho temps réel adressé à l’expéditeur.',
  })
  clientMessageId?: string;

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;
}

export class ConversationResponse implements ConversationDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  // L'autre participant.
  @ApiProperty({ type: UserSummaryResponse })
  participant!: UserSummaryResponse;

  // `direct` : envoi libre ; `requestSent` : demande envoyée, en attente ; `requestReceived` : demande reçue,
  // à accepter ou refuser (répondre l'accepte). Enum nommé sans description : elle produirait un `allOf`.
  @ApiProperty({ enum: ['direct', 'requestSent', 'requestReceived'], enumName: 'ConversationStatus' })
  status!: ConversationStatus;

  // Absent pour une conversation vide (ou supprimée pour soi depuis son dernier message).
  @ApiPropertyOptional({ type: MessageResponse })
  lastMessage?: MessageResponse;

  @ApiProperty({ type: 'integer', minimum: 0, description: 'Messages de l’autre participant non lus.' })
  unreadCount!: number;

  @ApiProperty({
    type: String,
    nullable: true,
    format: 'uuid',
    description: 'Dernier message lu par l’autre (« Vu »). Null tant que la conversation n’est pas acceptée.',
  })
  participantLastReadMessageId!: string | null;

  @ApiProperty({ description: 'Faux si l’un des deux a bloqué l’autre, ou si la demande envoyée a atteint sa limite.' })
  canSend!: boolean;

  @ApiProperty({
    type: 'integer',
    nullable: true,
    minimum: 0,
    description: 'Messages encore possibles dans une demande envoyée ; null hors demande envoyée.',
  })
  remainingRequestMessages!: number | null;

  @ApiProperty()
  blockedByMe!: boolean;

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;
}

export class ConversationPageResponse implements ConversationPageDto {
  @ApiProperty({ type: [ConversationResponse], description: 'De la plus récemment active à la plus ancienne, sans les conversations vides.' })
  items!: ConversationResponse[];

  @ApiProperty({ type: String, nullable: true, format: 'uuid', description: 'À renvoyer tel quel pour la page suivante ; null s’il n’y en a plus.' })
  nextCursor!: string | null;
}

export class MessagePageResponse implements MessagePageDto {
  @ApiProperty({ type: [MessageResponse], description: 'Du plus récent au plus ancien.' })
  items!: MessageResponse[];

  @ApiProperty({
    type: String,
    nullable: true,
    format: 'uuid',
    description: 'À renvoyer tel quel pour les messages plus anciens ; null s’il n’y en a plus.',
  })
  nextCursor!: string | null;
}

export class UnreadConversationsResponse implements UnreadConversationsDto {
  @ApiProperty({ type: 'integer', minimum: 0, description: 'Conversations (hors demandes) ayant au moins un message non lu.' })
  unreadCount!: number;

  @ApiProperty({ type: 'integer', minimum: 0, description: 'Demandes reçues en attente.' })
  requestCount!: number;
}

// Mappings explicites : rien n'est exposé par accident (ADR-003). Partagés par le controller et
// les événements WebSocket (AppMessagingEventPublisher).
export function toMessageDto({ message, sharedVideo, clientMessageId }: MessageItem): MessageDto {
  const dto: MessageDto = {
    id: message.id,
    conversationId: message.conversationId,
    senderId: message.senderId,
    content: message.content,
    createdAt: message.createdAt.toISOString(),
  };
  if (sharedVideo) dto.sharedVideo = toSharedVideoDto(sharedVideo);
  if (clientMessageId) dto.clientMessageId = clientMessageId;
  return dto;
}

function toSharedVideoDto({ id, video, author }: SharedVideo): SharedVideoDto {
  if (!video || !author) return { id, available: false, thumbnailUrl: null, hlsUrl: null, description: null };
  return {
    id,
    available: true,
    thumbnailUrl: video.thumbnailUrl,
    hlsUrl: video.hlsUrl,
    description: video.description,
    author: toUserSummary(author),
  };
}

export function toConversationDto(item: ConversationWithParticipant): ConversationDto {
  const dto: ConversationDto = {
    id: item.conversation.id,
    participant: toUserSummary(item.participant),
    status: item.status,
    unreadCount: item.conversation.unreadCount,
    participantLastReadMessageId: item.participantLastReadMessageId,
    canSend: item.canSend,
    remainingRequestMessages: item.remainingRequestMessages,
    blockedByMe: item.blockedByMe,
    createdAt: item.conversation.createdAt.toISOString(),
  };
  if (item.lastMessage) dto.lastMessage = toMessageDto(item.lastMessage);
  return dto;
}

export function toUnreadConversationsDto(badges: MessagingBadges): UnreadConversationsDto {
  return { unreadCount: badges.unreadConversations, requestCount: badges.pendingRequests };
}
