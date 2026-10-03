import type { UsersService } from '../../users/application/users.service';
import type { VideosService } from '../../videos/application/videos.service';
import {
  type ActivityEvent,
  groupKey,
  isModeration,
  type ModerationEvent,
  type Notification,
  type NotificationFilter,
  type NotificationGroup,
  type NotificationGroupWithContext,
  type NotificationWithContext,
  type RemovedNotification,
  type RetractableActivity,
} from '../domain/notification';
import type { NotificationPublisher } from '../domain/notification-publisher';
import type { NotificationRepository } from '../domain/notification.repository';
import type { SuspendedAccounts } from '../../../suspension/suspended-accounts';

export interface NotificationPage {
  items: NotificationWithContext[];
  nextCursor: string | null;
}

export interface NotificationGroupPage {
  items: NotificationGroupWithContext[];
  nextCursor: string | null;
}

// Service applicatif du centre d'activité (ADR-016, ADR-003).
// - Écriture : appelé par le module interactions après chaque interaction (notify) ou son annulation (retract).
// - Lecture : notifications du compte connecté, avec leurs auteurs et vidéos lus via `users` et `videos`.
// Stockage : une ligne par action. Le regroupement (« X et 12 autres ») est calculé à la lecture (`listGroups`).
// Chaque changement est poussé aux appareils connectés du destinataire (WebSocket, ADR-011) :
// nouvelle notification avec le badge, ou badge seul.
export class NotificationsService {
  constructor(
    private readonly notifications: NotificationRepository,
    private readonly users: UsersService,
    private readonly videos: VideosService,
    private readonly publisher: NotificationPublisher,
    private readonly suspended: SuspendedAccounts,
    private readonly now: () => Date = () => new Date(),
  ) {}

  // Personne n'est notifié de ses propres actions (liker sa vidéo, y commenter…).
  // Idempotent pour like, republication et follow : un second like ne crée pas de seconde notification,
  // et n'envoie rien.
  async notify(event: ActivityEvent): Promise<void> {
    if (event.actorId === event.recipientId) return;
    const created = await this.notifications.add(event);
    if (!created) return;
    const [item] = await this.withContext([created]);
    if (item) await this.publisher.notificationCreated(item, await this.countUnread(event.recipientId));
  }

  // Modération (ADR-038, module reports) : décision annoncée à la personne qui a signalé, ou contenu retiré annoncé à
  // son auteur. Sans auteur ; toujours créée, poussée en direct et en push comme les autres.
  async notifyModeration(event: ModerationEvent): Promise<void> {
    const created = await this.notifications.addModeration(event);
    const [item] = await this.withContext([created]);
    if (item) await this.publisher.notificationCreated(item, await this.countUnread(event.recipientId));
  }

  // Unlike, retrait d'une republication, unfollow : la notification disparaît, lue ou non.
  // Si l'action revient, `notify` en crée une nouvelle, en tête de liste.
  // Chaque suppression est annoncée à son destinataire avec le badge (ADR-043) : l'app la retire de son groupe.
  async retract(activity: RetractableActivity): Promise<void> {
    if (activity.actorId === activity.recipientId) return;
    await this.announceRemoved(await this.notifications.remove(activity));
  }

  // Blocage : les notifications échangées entre les deux comptes disparaissent.
  async removeBetween(userId: string, otherId: string): Promise<void> {
    await this.announceRemoved(await this.notifications.removeBetween(userId, otherId));
  }

  // Commentaire sur le point d'être supprimé (par son auteur, l'auteur de la vidéo ou un administrateur) : sa
  // notification est supprimée d'abord, pour être annoncée ; la cascade de la base l'emporterait sans prévenir.
  async retractComment(commentId: string): Promise<void> {
    await this.announceRemoved(await this.notifications.removeForComment(commentId));
  }

  // Du plus récent au plus ancien. Le curseur est l'identifiant de la dernière notification reçue
  // (UUID v7, ordonné dans le temps) : stable même si d'autres arrivent pendant le scroll.
  // `filter` : les notifications d'un groupe (sa liste complète).
  async list(recipientId: string, cursor: string | null, limit: number, filter: NotificationFilter = {}): Promise<NotificationPage> {
    const rows = await this.notifications.listForRecipient(recipientId, filter, cursor, limit + 1, await this.excludedActors());
    const page = rows.slice(0, limit);
    return {
      items: await this.withContext(page),
      nextCursor: rows.length > limit ? page.at(-1)!.id : null,
    };
  }

  // Groupes du plus récemment actif au plus ancien. Curseur : notification la plus récente du dernier groupe
  // reçu. Un groupe qui reçoit une nouvelle notification pendant le scroll remonte en tête : il peut alors
  // manquer dans les pages suivantes (l'app recharge la première page à chaque nouvelle notification).
  async listGroups(recipientId: string, cursor: string | null, limit: number): Promise<NotificationGroupPage> {
    const rows = await this.notifications.listGroups(recipientId, cursor, limit + 1, await this.excludedActors());
    const page = rows.slice(0, limit);
    return {
      items: await this.groupsWithContext(page),
      nextCursor: rows.length > limit ? page.at(-1)!.latest.id : null,
    };
  }

  unreadCount(recipientId: string): Promise<number> {
    return this.countUnread(recipientId);
  }

  // À l'ouverture du centre d'activité : l'app envoie la notification la plus récente qu'elle affiche.
  // Celles arrivées depuis restent non lues. Sans `upToId`, tout est marqué lu. Renvoie le nouveau badge,
  // aussi envoyé aux autres appareils connectés du compte.
  async markRead(recipientId: string, upToId: string | null): Promise<number> {
    await this.notifications.markRead(recipientId, upToId, this.now());
    return this.publishUnreadCount(recipientId);
  }

  // Les notifications des comptes suspendus (ADR-037) ne sont ni listées ni comptées ; elles réapparaissent à la
  // levée de la suspension. Le badge n'est pas renvoyé en direct au moment de la suspension : il est relu ensuite.
  private async excludedActors(): Promise<string[]> {
    return [...(await this.suspended.all())];
  }

  private async countUnread(recipientId: string): Promise<number> {
    return this.notifications.countUnread(recipientId, await this.excludedActors());
  }

  private async announceRemoved(removed: Notification[]): Promise<void> {
    const byRecipient = new Map<string, RemovedNotification[]>();
    for (const n of removed) {
      byRecipient.set(n.recipientId, [...(byRecipient.get(n.recipientId) ?? []), { id: n.id, key: groupKey(n), actorId: n.actorId }]);
    }
    for (const [recipientId, items] of byRecipient) {
      await this.publisher.notificationsRemoved(recipientId, items, await this.countUnread(recipientId));
    }
  }

  private async publishUnreadCount(recipientId: string): Promise<number> {
    const unreadCount = await this.countUnread(recipientId);
    await this.publisher.unreadCountChanged(recipientId, unreadCount);
    return unreadCount;
  }

  // Comme `withContext`. Un groupe dont la vidéo ou tous les auteurs affichés ont disparu est sauté.
  private async groupsWithContext(groups: NotificationGroup[]): Promise<NotificationGroupWithContext[]> {
    const actors = new Map((await this.users.getByIds([...new Set(groups.flatMap((g) => g.recentActorIds))])).map((u) => [u.id, u]));
    const videoIds = [...new Set(groups.flatMap((g) => (g.latest.videoId ? [g.latest.videoId] : [])))];
    const videos = new Map((await this.videos.getPublishedVideos(videoIds)).map((v) => [v.id, v]));
    return groups.flatMap((group) => {
      const groupActors = group.recentActorIds.flatMap((id) => actors.get(id) ?? []);
      const video = group.latest.videoId ? videos.get(group.latest.videoId) : null;
      // Une notification de modération n'a pas d'auteur.
      if ((groupActors.length === 0 && !isModeration(group.latest.type)) || video === undefined) return [];
      return [{ group, actors: groupActors, video }];
    });
  }

  // Auteurs et vidéos, lus via les modules users et videos (ADR-003). Compte ou vidéo supprimés
  // entre-temps : la cascade de la base supprime aussi la notification, elle est simplement sautée ici.
  private async withContext(notifications: Notification[]): Promise<NotificationWithContext[]> {
    const actors = new Map((await this.users.getByIds(notifications.flatMap((n) => (n.actorId ? [n.actorId] : [])))).map((u) => [u.id, u]));
    const videoIds = [...new Set(notifications.flatMap((n) => (n.videoId ? [n.videoId] : [])))];
    const videos = new Map((await this.videos.getPublishedVideos(videoIds)).map((v) => [v.id, v]));
    return notifications.flatMap((notification) => {
      const actor = notification.actorId ? (actors.get(notification.actorId) ?? null) : null;
      const video = notification.videoId ? videos.get(notification.videoId) : null;
      if ((!actor && !isModeration(notification.type)) || video === undefined) return [];
      return [{ notification, actor, video }];
    });
  }
}
