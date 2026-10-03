import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import type {
  NotificationCreatedEventDto,
  NotificationsRemovedEventDto,
  RemovedNotificationDto,
  UnreadNotificationsChangedEventDto,
} from '@repo/shared';
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

export class RemovedNotificationData implements RemovedNotificationDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty({ description: 'Clé du groupe de la notification, comme `NotificationGroupResponse.key`.' })
  key!: string;

  @ApiPropertyOptional({ format: 'uuid', description: 'Auteur de l’action ; absent pour une notification de modération.' })
  actorId?: string;
}

export class NotificationsRemovedData {
  @ApiProperty({ type: [RemovedNotificationData] })
  removed!: RemovedNotificationData[];

  @ApiProperty({ type: 'integer', minimum: 0, description: 'Badge à jour.' })
  unreadCount!: number;
}

// Notifications supprimées (ADR-043) : réaction ou abonnement retirés, blocage, commentaire supprimé.
export class NotificationsRemovedEvent implements NotificationsRemovedEventDto {
  @ApiProperty({ enum: ['notificationsRemoved'] })
  event!: 'notificationsRemoved';

  @ApiProperty({ type: NotificationsRemovedData })
  data!: NotificationsRemovedData;
}
