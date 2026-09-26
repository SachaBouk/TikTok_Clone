import type { ActivityEvent, Notification, NotificationFilter, NotificationGroup, RetractableActivity } from './notification';

// Port de la table notifications (ADR-006).
export abstract class NotificationRepository {
  // Idempotent pour like, republication et follow : au plus une notification par acteur et cible.
  // Renvoie la notification créée, ou null si elle existait déjà.
  abstract add(event: ActivityEvent): Promise<Notification | null>;
  // Sans effet si la notification n'existe pas. Renvoie true si une notification a été supprimée.
  abstract remove(activity: RetractableActivity): Promise<boolean>;

  // Supprime les notifications échangées entre deux comptes (blocage). Renvoie les destinataires touchés.
  abstract removeBetween(userId: string, otherId: string): Promise<string[]>;

  // Du plus récent au plus ancien, strictement avant `beforeId` s'il est donné (identifiants UUID v7, ordonnés).
  abstract listForRecipient(recipientId: string, filter: NotificationFilter, beforeId: string | null, limit: number): Promise<Notification[]>;
  // Groupes (voir `groupKey`), du plus récemment actif au plus ancien : ceux dont la notification la plus récente
  // est strictement avant `beforeId`. `recentActorIds` : `GROUP_ACTORS_SHOWN` au plus.
  abstract listGroups(recipientId: string, beforeId: string | null, limit: number): Promise<NotificationGroup[]>;
  abstract countUnread(recipientId: string): Promise<number>;
  // Marque lues les notifications non lues de `recipientId` jusqu'à `upToId` inclus (toutes s'il est null).
  abstract markRead(recipientId: string, upToId: string | null, readAt: Date): Promise<void>;
}
