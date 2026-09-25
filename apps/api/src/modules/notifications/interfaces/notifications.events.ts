import { ApiProperty } from '@nestjs/swagger';
import type { NotificationCreatedEventDto, UnreadNotificationsChangedEventDto } from '@repo/shared';
import { NotificationResponse, UnreadNotificationsResponse } from './notifications.responses';

// Schémas OpenAPI des événements WebSocket (ADR-011), rattachés à l'union `RealtimeEvent` (src/openapi).

export class NotificationCreatedData {
  @ApiProperty({ type: NotificationResponse })
  notification!: NotificationResponse;

  @ApiProperty({ type: 'integer', minimum: 0, description: 'Badge à jour.' })
  unreadCount!: number;
}

export class NotificationCreatedEvent implements NotificationCreatedEventDto {
  @ApiProperty({ enum: ['notificationCreated'] })
  event!: 'notificationCreated';

  @ApiProperty({ type: NotificationCreatedData })
  data!: NotificationCreatedData;
}

export class UnreadNotificationsChangedEvent implements UnreadNotificationsChangedEventDto {
  @ApiProperty({ enum: ['unreadNotificationsChanged'] })
  event!: 'unreadNotificationsChanged';

  @ApiProperty({ type: UnreadNotificationsResponse })
  data!: UnreadNotificationsResponse;
}
