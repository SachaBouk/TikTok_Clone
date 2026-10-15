import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import type {
  ConversationDto,
  ConversationKind,
  GroupDto,
  GroupEventDto,
  GroupEventType,
  GroupMemberDto,
  MessageSearchGroupDto,
  ConversationPageDto,
  ConversationStatus,
  MessageDto,
  MessageSearchResultDto,
  MessageSearchResultListDto,
  MessagePageDto,
  SharedVideoDto,
  UnreadConversationsDto,
} from '@repo/shared';
import { MessageLiveResponse, toMessageLiveDto } from '../../live/interfaces/live.responses';
import { MessageStoryResponse, toMessageStoryDto } from '../../stories/interfaces/stories.responses';
import { toUserSummary, UserSummaryResponse } from '../../users/interfaces/user-summary.response';
import type { ConversationWithParticipant, GroupInfo, MessageSearchResult } from '../application/messaging.service';
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

export class GroupEventResponse implements GroupEventDto {
  // `created` : groupe créé ; `added` / `removed` : membre ajouté ou retiré par l'expéditeur ; `left` : l'expéditeur a
  // quitté le groupe ; `renamed` : nouveau nom. Enum nommé sans description : elle produirait un `allOf`.
  @ApiProperty({ enum: ['created', 'added', 'removed', 'left', 'renamed'], enumName: 'GroupEventType' })
  type!: GroupEventType;

  // Membre ajouté ou retiré ; absent sinon, ou si son compte n'existe plus.
  @ApiPropertyOptional({ type: UserSummaryResponse })
  user?: UserSummaryResponse;

  @ApiPropertyOptional({ type: String, nullable: true, maxLength: 50, description: 'Nouveau nom d’un renommage (null : nom retiré).' })
  name?: string | null;
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

  @ApiPropertyOptional({ type: MessageStoryResponse })
  story?: MessageStoryResponse;

  // Live partagé (ADR-053).
  @ApiPropertyOptional({ type: MessageLiveResponse })
  live?: MessageLiveResponse;

  @ApiPropertyOptional({
    format: 'uuid',
    description: 'Identifiant d’envoi choisi par l’app (ADR-044) : seulement dans la réponse à l’envoi et l’écho temps réel adressé à l’expéditeur.',
  })
  clientMessageId?: string;

  // Dans un groupe (ADR-059) : l'expéditeur, absent si son compte n'existe plus.
  @ApiPropertyOptional({ type: UserSummaryResponse })
  sender?: UserSummaryResponse;

  // Ligne d'événement d'un groupe ; absent pour un message.
  @ApiPropertyOptional({ type: GroupEventResponse })
  event?: GroupEventResponse;

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;
}

export class GroupMemberResponse implements GroupMemberDto {
  @ApiProperty({ type: UserSummaryResponse })
  user!: UserSummaryResponse;

  @ApiProperty({ format: 'date-time' })
  joinedAt!: string;

  @ApiProperty({ type: String, nullable: true, format: 'uuid', description: 'Dernier message lu (« Vu par »).' })
  lastReadMessageId!: string | null;
}

export class GroupResponse implements GroupDto {
  @ApiProperty({ type: String, nullable: true, maxLength: 50, description: 'Nom du groupe ; null : l’app affiche les noms des membres.' })
  name!: string | null;

  @ApiProperty({ format: 'uuid', description: 'Administrateur : le membre le plus ancien.' })
  adminId!: string;

  @ApiProperty({ description: 'Groupe en sourdine pour le compte connecté (pas de notification push).' })
  muted!: boolean;

  @ApiProperty({ type: [GroupMemberResponse], description: 'Du plus ancien au plus récent, compte connecté compris.' })
  members!: GroupMemberResponse[];
}

export class ConversationResponse implements ConversationDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  // `direct` : conversation à deux ; `group` : chat de groupe (ADR-059).
  @ApiProperty({ enum: ['direct', 'group'], enumName: 'ConversationKind' })
  kind!: ConversationKind;

  // L'autre participant ; absent pour un groupe.
  @ApiPropertyOptional({ type: UserSummaryResponse })
  participant?: UserSummaryResponse;

  // Absent pour une conversation à deux.
  @ApiPropertyOptional({ type: GroupResponse })
  group?: GroupResponse;

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
export function toMessageDto({ message, sharedVideo, repliedStory, sharedLive, clientMessageId, sender, eventUser }: MessageItem): MessageDto {
  const dto: MessageDto = {
    id: message.id,
    conversationId: message.conversationId,
    senderId: message.senderId,
    content: message.content,
    createdAt: message.createdAt.toISOString(),
  };
  if (sharedVideo) dto.sharedVideo = toSharedVideoDto(sharedVideo);
  if (repliedStory) dto.story = toMessageStoryDto(repliedStory.id, repliedStory.story ?? undefined);
  if (sharedLive) dto.live = toMessageLiveDto(sharedLive.id, sharedLive.item);
  if (clientMessageId) dto.clientMessageId = clientMessageId;
  if (sender) dto.sender = toUserSummary(sender);
  if (message.event) {
    const event: GroupEventDto = { type: message.event };
    if (eventUser) event.user = toUserSummary(eventUser);
    if (message.event === 'renamed') event.name = message.content || null;
    dto.event = event;
  }
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
    kind: item.conversation.kind,
    status: item.status,
    unreadCount: item.conversation.unreadCount,
    participantLastReadMessageId: item.participantLastReadMessageId,
    canSend: item.canSend,
    remainingRequestMessages: item.remainingRequestMessages,
    blockedByMe: item.blockedByMe,
    createdAt: item.conversation.createdAt.toISOString(),
  };
  if (item.participant) dto.participant = toUserSummary(item.participant);
  if (item.group) dto.group = toGroupDto(item.group);
  if (item.lastMessage) dto.lastMessage = toMessageDto(item.lastMessage);
  return dto;
}

function toGroupDto(group: GroupInfo): GroupDto {
  return {
    name: group.name,
    adminId: group.adminId,
    muted: group.muted,
    members: group.members.map((m) => ({ user: toUserSummary(m.user), joinedAt: m.joinedAt.toISOString(), lastReadMessageId: m.lastReadMessageId })),
  };
}

export function toUnreadConversationsDto(badges: MessagingBadges): UnreadConversationsDto {
  return { unreadCount: badges.unreadConversations, requestCount: badges.pendingRequests };
}

export class MessageSearchGroupResponse implements MessageSearchGroupDto {
  @ApiProperty({ type: String, nullable: true })
  name!: string | null;

  @ApiProperty({ type: [UserSummaryResponse], description: 'Membres, du plus ancien au plus récent.' })
  members!: UserSummaryResponse[];
}

export class MessageSearchResultResponse implements MessageSearchResultDto {
  @ApiProperty({ format: 'uuid' })
  conversationId!: string;

  @ApiProperty({ format: 'uuid' })
  messageId!: string;

  @ApiProperty()
  content!: string;

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;

  @ApiProperty({ type: UserSummaryResponse })
  participant!: UserSummaryResponse;

  @ApiProperty({ type: UserSummaryResponse })
  sender!: UserSummaryResponse;

  // Message d'un groupe (ADR-059) ; absent sinon.
  @ApiPropertyOptional({ type: MessageSearchGroupResponse })
  group?: MessageSearchGroupResponse;
}

export class MessageSearchResultListResponse implements MessageSearchResultListDto {
  @ApiProperty({ type: [MessageSearchResultResponse], description: 'Du plus récent au plus ancien.' })
  items!: MessageSearchResultResponse[];
}

export function toMessageSearchResultDto({ message, participant, sender, group }: MessageSearchResult): MessageSearchResultDto {
  const dto: MessageSearchResultDto = {
    conversationId: message.conversationId,
    messageId: message.id,
    content: message.content,
    createdAt: message.createdAt.toISOString(),
    participant: toUserSummary(participant),
    sender: toUserSummary(sender),
  };
  if (group) dto.group = { name: group.name, members: group.members.map(toUserSummary) };
  return dto;
}
