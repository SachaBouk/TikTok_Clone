import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsUUID, Max, Min } from 'class-validator';
import { DEFAULT_NOTIFICATIONS_PAGE_SIZE, MAX_NOTIFICATIONS_PAGE_SIZE } from '../domain/notification';

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
