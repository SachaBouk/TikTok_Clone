import { randomUUID } from 'node:crypto';
import { GROUP_ACTORS_SHOWN, groupKey, type ActivityEvent, type Notification, type NotificationFilter, type NotificationGroup, type RetractableActivity } from '../domain/notification';
import { NotificationRepository } from '../domain/notification.repository';

// Adaptateur en mémoire pour les tests. Reproduit les index uniques partiels de la base :
// au plus une notification par (acteur, vidéo) pour un like ou une republication, par (acteur, compte) pour un follow.
export class InMemoryNotificationRepository extends NotificationRepository {
  readonly notifications = new Map<string, Notification>();
  private sequence = 0;

  async add(event: ActivityEvent): Promise<Notification | null> {
    if (event.type !== 'comment' && this.find(event)) return null;
    // Identifiants croissants, comme les UUID v7 de la base.
    const id = `${String(++this.sequence).padStart(8, '0')}-${randomUUID()}`;
    const created: Notification = {
      id,
      recipientId: event.recipientId,
      actorId: event.actorId,
      type: event.type,
      videoId: event.type === 'follow' ? null : event.videoId,
      commentId: event.type === 'comment' ? event.commentId : null,
      commentText: event.type === 'comment' ? event.commentText : null,
      readAt: null,
      createdAt: new Date(),
    };
    this.notifications.set(id, created);
    return created;
  }

  async remove(activity: RetractableActivity): Promise<boolean> {
    const found = this.find(activity);
    return found ? this.notifications.delete(found.id) : false;
  }

  async removeBetween(userId: string, otherId: string): Promise<string[]> {
    const recipients = new Set<string>();
    for (const [id, n] of this.notifications) {
      if ((n.recipientId === userId && n.actorId === otherId) || (n.recipientId === otherId && n.actorId === userId)) {
        this.notifications.delete(id);
        recipients.add(n.recipientId);
      }
    }
    return [...recipients];
  }

  async listForRecipient(recipientId: string, filter: NotificationFilter, beforeId: string | null, limit: number): Promise<Notification[]> {
    return this.newestFirst(recipientId)
      .filter((n) => (!filter.type || n.type === filter.type) && (!filter.videoId || n.videoId === filter.videoId))
      .filter((n) => !beforeId || n.id < beforeId)
      .slice(0, limit);
  }

  async listGroups(recipientId: string, beforeId: string | null, limit: number): Promise<NotificationGroup[]> {
    const groups = new Map<string, NotificationGroup>();
    for (const n of this.newestFirst(recipientId)) {
      const group = groups.get(groupKey(n));
      if (!group) {
        groups.set(groupKey(n), { latest: n, count: 1, unread: !n.readAt, recentActorIds: [n.actorId] });
        continue;
      }
      group.count += 1;
      group.unread ||= !n.readAt;
      if (group.recentActorIds.length < GROUP_ACTORS_SHOWN) group.recentActorIds.push(n.actorId);
    }
    return [...groups.values()].filter((g) => !beforeId || g.latest.id < beforeId).slice(0, limit);
  }

  private newestFirst(recipientId: string): Notification[] {
    return [...this.notifications.values()].filter((n) => n.recipientId === recipientId).sort((a, b) => (a.id < b.id ? 1 : -1));
  }

  async countUnread(recipientId: string): Promise<number> {
    return [...this.notifications.values()].filter((n) => n.recipientId === recipientId && !n.readAt).length;
  }

  async markRead(recipientId: string, upToId: string | null, readAt: Date): Promise<void> {
    for (const n of this.notifications.values()) {
      if (n.recipientId === recipientId && !n.readAt && (!upToId || n.id <= upToId)) n.readAt = readAt;
    }
  }

  private find(activity: RetractableActivity): Notification | undefined {
    return [...this.notifications.values()].find(
      (n) =>
        n.type === activity.type &&
        n.actorId === activity.actorId &&
        (activity.type === 'follow' ? n.recipientId === activity.recipientId : n.videoId === activity.videoId),
    );
  }
}
