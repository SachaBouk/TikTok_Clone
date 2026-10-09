import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import type {
  NotificationCommentDto,
  NotificationDto,
  NotificationGiftDto,
  NotificationLiveDto,
  NotificationGroupDto,
  ModerationOutcome,
  NotificationGroupPageDto,
  NotificationModerationDto,
  NotificationPageDto,
  NotificationType,
  NotificationVideoDto,
  ReportReason,
  ReportTargetType,
  UnreadNotificationsDto,
} from '@repo/shared';
import { toUserSummary, UserSummaryResponse } from '../../users/interfaces/user-summary.response';
import { giftDisplay } from '../../wallet/domain/gift-catalog';
import {
  groupKey,
  MODERATION_OUTCOMES,
  MODERATION_REASONS,
  MODERATION_TARGET_TYPES,
  type Notification,
  NOTIFICATION_TYPES,
  type NotificationGroupWithContext,
  type NotificationWithContext,
} from '../domain/notification';

// Schémas OpenAPI des DTO partagés : `implements` garantit à la compilation que chaque classe suit son type.

export class NotificationVideoResponse implements NotificationVideoDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty({ format: 'uri' })
  thumbnailUrl!: string;
}

export class NotificationCommentResponse implements NotificationCommentDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty()
  content!: string;
}

// Notification de modération (ADR-038). Enums nommés sans description (sinon `allOf`).
export class NotificationModerationResponse implements NotificationModerationDto {
  @ApiProperty({ enum: MODERATION_TARGET_TYPES, enumName: 'ReportTargetType' })
  targetType!: ReportTargetType;

  // Contenu retiré : motif choisi par l'administrateur.
  @ApiPropertyOptional({ enum: MODERATION_REASONS, enumName: 'ReportReason' })
  reason?: ReportReason;

  // Signalement examiné : décision.
  @ApiPropertyOptional({ enum: MODERATION_OUTCOMES, enumName: 'ModerationOutcome' })
  outcome?: ModerationOutcome;

  @ApiPropertyOptional({ description: 'Texte du contenu concerné, copié.' })
  excerpt?: string;
}

// Cadeau reçu (ADR-050).
export class NotificationGiftResponse implements NotificationGiftDto {
  @ApiProperty({ description: 'Code du catalogue.' })
  code!: string;

  @ApiProperty({ description: 'Nom du cadeau (« Cadeau » pour un code retiré du catalogue).' })
  name!: string;

  @ApiProperty()
  emoji!: string;

  @ApiProperty({ type: 'integer', minimum: 1, description: 'Prix payé, en jetons.' })
  amount!: number;
}

// Live lancé (ADR-053).
export class NotificationLiveResponse implements NotificationLiveDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;
}

export class NotificationResponse implements NotificationDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  // `kind` plutôt que `type` : le générateur Swift renommerait `type` en `_type`.
  @ApiProperty({ enum: NOTIFICATION_TYPES, enumName: 'NotificationType' })
  kind!: NotificationType;

  // Auteur de l'action ; absent pour une notification de modération. Objets imbriqués sans description : elle
  // produirait un `allOf`, que le client Swift envelopperait (voir CLAUDE.md).
  @ApiPropertyOptional({ type: UserSummaryResponse })
  actor?: UserSummaryResponse;

  // Absent pour un follow.
  @ApiPropertyOptional({ type: NotificationVideoResponse })
  video?: NotificationVideoResponse;

  // Présent pour un commentaire seulement.
  @ApiPropertyOptional({ type: NotificationCommentResponse })
  comment?: NotificationCommentResponse;

  // Présent pour une notification de modération seulement.
  @ApiPropertyOptional({ type: NotificationModerationResponse })
  moderation?: NotificationModerationResponse;

  // Présent pour un cadeau seulement.
  @ApiPropertyOptional({ type: NotificationGiftResponse })
  gift?: NotificationGiftResponse;

  // Présent pour un live seulement.
  @ApiPropertyOptional({ type: NotificationLiveResponse })
  live?: NotificationLiveResponse;

  @ApiProperty()
  read!: boolean;

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;
}

export class NotificationPageResponse implements NotificationPageDto {
  @ApiProperty({ type: [NotificationResponse], description: 'Du plus récent au plus ancien.' })
  items!: NotificationResponse[];

  @ApiProperty({ type: String, nullable: true, format: 'uuid', description: 'À renvoyer tel quel pour la page suivante ; null s’il n’y en a plus.' })
  nextCursor!: string | null;
}

export class NotificationGroupResponse implements NotificationGroupDto {
  @ApiProperty({
    description:
      'Identifiant stable du groupe : `like:<videoId>`, `repost:<videoId>`, `gift:<videoId>`, `follow`, `comment:<notificationId>`, `live:<liveId>`, `moderation:<notificationId>`.',
  })
  key!: string;

  @ApiProperty({ enum: NOTIFICATION_TYPES, enumName: 'NotificationType' })
  kind!: NotificationType;

  @ApiProperty({ type: [UserSummaryResponse], description: 'Auteurs des notifications les plus récentes, 2 au plus, du plus récent au plus ancien.' })
  actors!: UserSummaryResponse[];

  @ApiProperty({ type: 'integer', minimum: 1, description: 'Nombre de notifications du groupe.' })
  count!: number;

  // Like, republication, commentaire.
  @ApiPropertyOptional({ type: NotificationVideoResponse })
  video?: NotificationVideoResponse;

  // Groupe d'un commentaire (toujours seul).
  @ApiPropertyOptional({ type: NotificationCommentResponse })
  comment?: NotificationCommentResponse;

  // Notification de modération (toujours seule, `actors` vide).
  @ApiPropertyOptional({ type: NotificationModerationResponse })
  moderation?: NotificationModerationResponse;

  // Cadeau de la notification la plus récente du groupe.
  @ApiPropertyOptional({ type: NotificationGiftResponse })
  gift?: NotificationGiftResponse;

  // Live (groupe toujours seul).
  @ApiPropertyOptional({ type: NotificationLiveResponse })
  live?: NotificationLiveResponse;

  @ApiProperty({ description: 'Faux si au moins une notification du groupe n’est pas lue.' })
  read!: boolean;

  @ApiProperty({ format: 'uuid', description: 'Notification la plus récente du groupe : à envoyer à `markNotificationsRead`.' })
  latestId!: string;

  @ApiProperty({ format: 'date-time', description: 'Date de la notification la plus récente.' })
  createdAt!: string;
}

export class NotificationGroupPageResponse implements NotificationGroupPageDto {
  @ApiProperty({ type: [NotificationGroupResponse], description: 'Du groupe le plus récemment actif au plus ancien.' })
  items!: NotificationGroupResponse[];

  @ApiProperty({ type: String, nullable: true, format: 'uuid', description: 'À renvoyer tel quel pour la page suivante ; null s’il n’y en a plus.' })
  nextCursor!: string | null;
}

export class UnreadNotificationsResponse implements UnreadNotificationsDto {
  @ApiProperty({ type: 'integer', minimum: 0 })
  unreadCount!: number;
}

// Mapping explicite : rien n'est exposé par accident (ADR-003). Partagé par le controller et
// les événements WebSocket (RealtimeNotificationPublisher).
export function toNotificationDto({ notification, actor, video }: NotificationWithContext): NotificationDto {
  const dto: NotificationDto = {
    id: notification.id,
    kind: notification.type,
    read: notification.readAt !== null,
    createdAt: notification.createdAt.toISOString(),
  };
  if (actor) dto.actor = toUserSummary(actor);
  const moderation = toModerationDto(notification);
  if (moderation) dto.moderation = moderation;
  const gift = toGiftDto(notification);
  if (gift) dto.gift = gift;
  if (notification.liveId) dto.live = { id: notification.liveId };
  if (video) dto.video = { id: video.id, thumbnailUrl: video.thumbnailUrl };
  if (notification.commentId && notification.commentText !== null) {
    dto.comment = { id: notification.commentId, content: notification.commentText };
  }
  return dto;
}

export function toNotificationGroupDto({ group, actors, video }: NotificationGroupWithContext): NotificationGroupDto {
  const { latest } = group;
  const dto: NotificationGroupDto = {
    key: groupKey(latest),
    kind: latest.type,
    actors: actors.map(toUserSummary),
    count: group.count,
    read: !group.unread,
    latestId: latest.id,
    createdAt: latest.createdAt.toISOString(),
  };
  if (video) dto.video = { id: video.id, thumbnailUrl: video.thumbnailUrl };
  if (latest.type === 'comment' && latest.commentId && latest.commentText !== null) {
    dto.comment = { id: latest.commentId, content: latest.commentText };
  }
  const moderation = toModerationDto(latest);
  if (moderation) dto.moderation = moderation;
  const gift = toGiftDto(latest);
  if (gift) dto.gift = gift;
  if (latest.liveId) dto.live = { id: latest.liveId };
  return dto;
}

function toGiftDto({ gift }: Notification): NotificationGiftDto | null {
  if (!gift) return null;
  const display = giftDisplay(gift.code);
  return { code: gift.code, name: display.name, emoji: display.emoji, amount: gift.amount };
}

function toModerationDto({ moderation }: Notification): NotificationModerationDto | null {
  if (!moderation) return null;
  return {
    targetType: moderation.targetType,
    ...(moderation.reason ? { reason: moderation.reason } : {}),
    ...(moderation.outcome ? { outcome: moderation.outcome } : {}),
    ...(moderation.excerpt ? { excerpt: moderation.excerpt } : {}),
  };
}
