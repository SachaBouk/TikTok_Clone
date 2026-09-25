import type { UsersService } from '../../users/application/users.service';
import type { VideosService } from '../../videos/application/videos.service';
import type { ActivityEvent, Notification, NotificationWithContext, RetractableActivity } from '../domain/notification';
import type { NotificationPublisher } from '../domain/notification-publisher';
import type { NotificationRepository } from '../domain/notification.repository';

export interface NotificationPage {
  items: NotificationWithContext[];
  nextCursor: string | null;
}

// Service applicatif du centre d'activité (ADR-016, ADR-003).
// - Écriture : appelé par le module interactions après chaque interaction (notify) ou son annulation (retract).
// - Lecture : notifications du compte connecté, avec leurs auteurs et vidéos lus via `users` et `videos`.
// Pas de regroupement (« X et 12 autres ») : une ligne par action.
// Chaque changement est poussé aux appareils connectés du destinataire (WebSocket, ADR-011) :
// nouvelle notification avec le badge, ou badge seul.
export class NotificationsService {
  constructor(
    private readonly notifications: NotificationRepository,
    private readonly users: UsersService,
    private readonly videos: VideosService,
    private readonly publisher: NotificationPublisher,
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
    if (item) await this.publisher.notificationCreated(item, await this.notifications.countUnread(event.recipientId));
  }

  // Unlike, retrait d'une republication, unfollow : la notification disparaît, lue ou non.
  // Si l'action revient, `notify` en crée une nouvelle, en tête de liste.
  async retract(activity: RetractableActivity): Promise<void> {
    if (activity.actorId === activity.recipientId) return;
    if (await this.notifications.remove(activity)) await this.publishUnreadCount(activity.recipientId);
  }

  // Blocage : les notifications échangées entre les deux comptes disparaissent ; les badges touchés sont renvoyés.
  async removeBetween(userId: string, otherId: string): Promise<void> {
    for (const recipientId of await this.notifications.removeBetween(userId, otherId)) await this.publishUnreadCount(recipientId);
  }

  // Du plus récent au plus ancien. Le curseur est l'identifiant de la dernière notification reçue
  // (UUID v7, ordonné dans le temps) : stable même si d'autres arrivent pendant le scroll.
  async list(recipientId: string, cursor: string | null, limit: number): Promise<NotificationPage> {
    const rows = await this.notifications.listForRecipient(recipientId, cursor, limit + 1);
    const page = rows.slice(0, limit);
    return {
      items: await this.withContext(page),
      nextCursor: rows.length > limit ? page.at(-1)!.id : null,
    };
  }

  unreadCount(recipientId: string): Promise<number> {
    return this.notifications.countUnread(recipientId);
  }

  // À l'ouverture du centre d'activité : l'app envoie la notification la plus récente qu'elle affiche.
  // Celles arrivées depuis restent non lues. Sans `upToId`, tout est marqué lu. Renvoie le nouveau badge,
  // aussi envoyé aux autres appareils connectés du compte.
  async markRead(recipientId: string, upToId: string | null): Promise<number> {
    await this.notifications.markRead(recipientId, upToId, this.now());
    return this.publishUnreadCount(recipientId);
  }

  private async publishUnreadCount(recipientId: string): Promise<number> {
    const unreadCount = await this.notifications.countUnread(recipientId);
    await this.publisher.unreadCountChanged(recipientId, unreadCount);
    return unreadCount;
  }

  // Auteurs et vidéos, lus via les modules users et videos (ADR-003). Compte ou vidéo supprimés
  // entre-temps : la cascade de la base supprime aussi la notification, elle est simplement sautée ici.
  private async withContext(notifications: Notification[]): Promise<NotificationWithContext[]> {
    const actors = new Map((await this.users.getByIds(notifications.map((n) => n.actorId))).map((u) => [u.id, u]));
    const videoIds = [...new Set(notifications.flatMap((n) => (n.videoId ? [n.videoId] : [])))];
    const videos = new Map((await this.videos.getPublishedVideos(videoIds)).map((v) => [v.id, v]));
    return notifications.flatMap((notification) => {
      const actor = actors.get(notification.actorId);
      const video = notification.videoId ? videos.get(notification.videoId) : null;
      if (!actor || video === undefined) return [];
      return [{ notification, actor, video }];
    });
  }
}
