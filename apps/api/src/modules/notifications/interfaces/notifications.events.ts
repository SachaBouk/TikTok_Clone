import { ApiProperty } from '@nestjs/swagger';
import type {
  NotificationCreatedEventDto,
  NotificationsRemovedEventDto,
  RemovedNotificationDto,
  UnreadNotificationsChangedEventDto,
} from '@repo/shared';
import { NotificationGroupResponse, NotificationResponse, UnreadNotificationsResponse } from './notifications.responses';

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
}

export class NotificationsRemovedData {
  @ApiProperty({ type: [RemovedNotificationData] })
  removed!: RemovedNotificationData[];

  @ApiProperty({
    type: [NotificationGroupResponse],
    description: 'État recalculé des groupes touchés qui ne sont pas vides ; un groupe touché absent est vide.',
  })
  groups!: NotificationGroupResponse[];

  @ApiProperty({ type: 'integer', minimum: 0, description: 'Badge à jour.' })
  unreadCount!: number;
}

// Notifications supprimées (ADR-043) : réaction ou abonnement retirés, blocage, commentaire, vidéo ou compte supprimés.
export class NotificationsRemovedEvent implements NotificationsRemovedEventDto {
  @ApiProperty({ enum: ['notificationsRemoved'] })
  event!: 'notificationsRemoved';

  @ApiProperty({ type: NotificationsRemovedData })
  data!: NotificationsRemovedData;
}
