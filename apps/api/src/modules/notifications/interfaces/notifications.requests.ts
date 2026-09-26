import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsUUID, Max, Min } from 'class-validator';
import { DEFAULT_NOTIFICATIONS_PAGE_SIZE, MAX_NOTIFICATIONS_PAGE_SIZE, type NotificationType } from '../domain/notification';

const NOTIFICATION_TYPES: NotificationType[] = ['like', 'comment', 'follow', 'repost'];

// Corps et paramètres de requête validés par le ValidationPipe global (main.ts).

export class NotificationsQuery {
  @ApiPropertyOptional({ format: 'uuid', description: '`nextCursor` de la page précédente.' })
  @IsOptional()
  @IsUUID()
  cursor?: string;

  @ApiPropertyOptional({ type: 'integer', minimum: 1, maximum: MAX_NOTIFICATIONS_PAGE_SIZE, default: DEFAULT_NOTIFICATIONS_PAGE_SIZE })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(MAX_NOTIFICATIONS_PAGE_SIZE)
  limit: number = DEFAULT_NOTIFICATIONS_PAGE_SIZE;
}

// Liste complète d'un groupe : son type, et sa vidéo pour un like ou une republication.
export class NotificationListQuery extends NotificationsQuery {
  // Pas de description : sur un enum nommé, elle produirait un `allOf` (voir CLAUDE.md).
  @ApiPropertyOptional({ enum: NOTIFICATION_TYPES, enumName: 'NotificationType' })
  @IsOptional()
  @IsIn(NOTIFICATION_TYPES)
  kind?: NotificationType;

  @ApiPropertyOptional({ format: 'uuid' })
  @IsOptional()
  @IsUUID()
  videoId?: string;
}

export class MarkNotificationsReadRequest {
  @ApiPropertyOptional({
    format: 'uuid',
    description:
      'Notification la plus récente affichée : elle et les plus anciennes passent en lues, celles arrivées depuis restent non lues. Absent : toutes.',
  })
  @IsOptional()
  @IsUUID()
  upToId?: string;
}
