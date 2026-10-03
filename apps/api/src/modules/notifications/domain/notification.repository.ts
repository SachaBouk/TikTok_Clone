import type { ActivityEvent, ModerationEvent, Notification, NotificationFilter, NotificationGroup, RetractableActivity } from './notification';

// Port de la table notifications (ADR-006).
export abstract class NotificationRepository {
  // Idempotent pour like, republication et follow : au plus une notification par acteur et cible.
  // Renvoie la notification créée, ou null si elle existait déjà.
  abstract add(event: ActivityEvent): Promise<Notification | null>;
  // Notification de modération (ADR-038) : toujours créée.
  abstract addModeration(event: ModerationEvent): Promise<Notification>;
  // Les suppressions renvoient les notifications supprimées (vide si aucune), pour les retirer en direct (ADR-043).
  // Retrait d'une réaction ou d'un abonnement.
  abstract remove(activity: RetractableActivity): Promise<Notification[]>;
  // Notifications échangées entre deux comptes (blocage).
  abstract removeBetween(userId: string, otherId: string): Promise<Notification[]>;
  // Notification d'un commentaire, avant sa suppression (sinon la cascade l'emporterait sans prévenir).
  abstract removeForComment(commentId: string): Promise<Notification[]>;

  // Lectures : sans les notifications des auteurs `excludedActorIds` (comptes suspendus, ADR-037 ; une notification de
  // modération, sans auteur, n'est jamais exclue), qui ne comptent
  // ni dans les groupes ni dans le badge.
  // Du plus récent au plus ancien, strictement avant `beforeId` s'il est donné (identifiants UUID v7, ordonnés).
  abstract listForRecipient(
    recipientId: string,
    filter: NotificationFilter,
    beforeId: string | null,
    limit: number,
    excludedActorIds: string[],
  ): Promise<Notification[]>;
  // Groupes (voir `groupKey`), du plus récemment actif au plus ancien : ceux dont la notification la plus récente
  // est strictement avant `beforeId`. `recentActorIds` : `GROUP_ACTORS_SHOWN` au plus.
  abstract listGroups(recipientId: string, beforeId: string | null, limit: number, excludedActorIds: string[]): Promise<NotificationGroup[]>;
  abstract countUnread(recipientId: string, excludedActorIds: string[]): Promise<number>;
  // Marque lues les notifications non lues de `recipientId` jusqu'à `upToId` inclus (toutes s'il est null).
  abstract markRead(recipientId: string, upToId: string | null, readAt: Date): Promise<void>;
}
