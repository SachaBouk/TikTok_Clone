import { ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsUUID, Max, Min } from 'class-validator';
import { DEFAULT_NOTIFICATIONS_PAGE_SIZE, MAX_NOTIFICATIONS_PAGE_SIZE, type NotificationType } from '../domain/notification';
import { NOTIFICATION_TYPES } from '../domain/notification';

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

// Groupes, filtrés par type (écran d'activité, ADR-058) : `kind` répété ; absent, tous les types.
export class NotificationGroupsQuery extends NotificationsQuery {
  @ApiPropertyOptional({ enum: NOTIFICATION_TYPES, enumName: 'NotificationType', isArray: true })
  @IsOptional()
  @Transform(({ value }: { value: unknown }) => (value === undefined ? undefined : Array.isArray(value) ? value : [value]))
  @IsIn(NOTIFICATION_TYPES, { each: true })
  kind?: NotificationType[];
}

// Liste complète d'un groupe : son type, et sa vidéo pour un like ou une republication, son commentaire pour un j'aime
// de commentaire (ADR-060).
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

  @ApiPropertyOptional({ format: 'uuid' })
  @IsOptional()
  @IsUUID()
  commentId?: string;
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
