import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import type {
  NotificationCommentDto,
  NotificationDto,
  NotificationGroupDto,
  NotificationGroupPageDto,
  NotificationPageDto,
  NotificationType,
  NotificationVideoDto,
  UnreadNotificationsDto,
} from '@repo/shared';
import { toUserSummary, UserSummaryResponse } from '../../users/interfaces/user-summary.response';
import { groupKey, type NotificationGroupWithContext, type NotificationWithContext } from '../domain/notification';

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

export class NotificationResponse implements NotificationDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  // `kind` plutôt que `type` : le générateur Swift renommerait `type` en `_type`.
  @ApiProperty({ enum: ['like', 'comment', 'follow', 'repost'], enumName: 'NotificationType' })
  kind!: NotificationType;

  // Auteur de l'action. Objets imbriqués sans description : elle produirait un `allOf`,
  // que le client Swift envelopperait (voir CLAUDE.md).
  @ApiProperty({ type: UserSummaryResponse })
  actor!: UserSummaryResponse;

  // Absent pour un follow.
  @ApiPropertyOptional({ type: NotificationVideoResponse })
  video?: NotificationVideoResponse;

  // Présent pour un commentaire seulement.
  @ApiPropertyOptional({ type: NotificationCommentResponse })
  comment?: NotificationCommentResponse;

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
  @ApiProperty({ description: 'Identifiant stable du groupe : `like:<videoId>`, `repost:<videoId>`, `follow`, `comment:<notificationId>`.' })
  key!: string;

  @ApiProperty({ enum: ['like', 'comment', 'follow', 'repost'], enumName: 'NotificationType' })
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
    actor: toUserSummary(actor),
    read: notification.readAt !== null,
    createdAt: notification.createdAt.toISOString(),
  };
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
  return dto;
}
