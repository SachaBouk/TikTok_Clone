import type { NotificationWithContext } from '../domain/notification';
import { NotificationPublisher } from '../domain/notification-publisher';

// Adaptateur en mémoire pour les tests : garde les événements publiés.
export class InMemoryNotificationPublisher extends NotificationPublisher {
  readonly created: { item: NotificationWithContext; unreadCount: number }[] = [];
  readonly unreadCounts: { recipientId: string; unreadCount: number }[] = [];

  async notificationCreated(item: NotificationWithContext, unreadCount: number): Promise<void> {
    this.created.push({ item, unreadCount });
  }

  async unreadCountChanged(recipientId: string, unreadCount: number): Promise<void> {
    this.unreadCounts.push({ recipientId, unreadCount });
  }
}
