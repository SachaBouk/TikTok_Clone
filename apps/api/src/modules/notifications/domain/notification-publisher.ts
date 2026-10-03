import type { NotificationWithContext, RemovedNotification } from './notification';

// Événements vers les appareils connectés du destinataire (WebSocket, ADR-011). Au mieux : sans connexion,
// ils sont perdus, et l'app relit le centre d'activité et le badge par l'API REST.
export abstract class NotificationPublisher {
  abstract notificationCreated(item: NotificationWithContext, unreadCount: number): Promise<void>;
  // Badge changé sans nouvelle notification (marquage lu).
  abstract unreadCountChanged(recipientId: string, unreadCount: number): Promise<void>;
  // Notifications supprimées (ADR-043), avec le badge à jour.
  abstract notificationsRemoved(recipientId: string, removed: RemovedNotification[], unreadCount: number): Promise<void>;
}
