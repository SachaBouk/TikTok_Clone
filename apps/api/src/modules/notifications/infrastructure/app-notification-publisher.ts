import { Injectable } from '@nestjs/common';
import { PUSH_BODY_MAX_LENGTH } from '../../push/domain/push';
import { PushService } from '../../push/application/push.service';
import { RealtimeService } from '../../realtime/application/realtime.service';
import type { NotificationWithContext } from '../domain/notification';
import { NotificationPublisher } from '../domain/notification-publisher';
import { toNotificationDto } from '../interfaces/notifications.responses';

// Prévient le destinataire sur ses appareils : WebSocket (module realtime, ADR-011), au même format que
// `GET /notifications`, et notification push (module push) pour une nouvelle notification.
@Injectable()
export class AppNotificationPublisher extends NotificationPublisher {
  constructor(
    private readonly realtime: RealtimeService,
    private readonly push: PushService,
  ) {
    super();
  }

  async notificationCreated(item: NotificationWithContext, unreadCount: number): Promise<void> {
    const { notification, actor } = item;
    await this.realtime.sendToUser(notification.recipientId, {
      event: 'notificationCreated',
      data: { notification: toNotificationDto(item), unreadCount },
    });
    await this.push.notify(notification.recipientId, {
      title: actor.displayName,
      body: pushBody(item),
      threadId: 'activity',
      data: { type: 'notification', notificationId: notification.id, kind: notification.type, ...(notification.videoId ? { videoId: notification.videoId } : {}) },
    });
  }

  unreadCountChanged(recipientId: string, unreadCount: number): Promise<void> {
    return this.realtime.sendToUser(recipientId, { event: 'unreadNotificationsChanged', data: { unreadCount } });
  }
}

function pushBody({ notification }: NotificationWithContext): string {
  switch (notification.type) {
    case 'like':
      return 'a aimé ta vidéo';
    case 'repost':
      return 'a republié ta vidéo';
    case 'follow':
      return 'a commencé à te suivre';
    case 'comment':
      return `a commenté : ${notification.commentText ?? ''}`.slice(0, PUSH_BODY_MAX_LENGTH);
  }
}
