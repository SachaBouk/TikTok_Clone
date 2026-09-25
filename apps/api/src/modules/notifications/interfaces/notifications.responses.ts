import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import type {
  NotificationCommentDto,
  NotificationDto,
  NotificationPageDto,
  NotificationType,
  NotificationVideoDto,
  UnreadNotificationsDto,
} from '@repo/shared';
import { toUserSummary, UserSummaryResponse } from '../../users/interfaces/user-summary.response';
import type { NotificationWithContext } from '../domain/notification';

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
