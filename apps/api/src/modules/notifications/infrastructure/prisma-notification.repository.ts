import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../../database/prisma.service';
import type { ActivityEvent, Notification, RetractableActivity } from '../domain/notification';
import { NotificationRepository } from '../domain/notification.repository';

const notificationSelect = {
  id: true,
  userId: true,
  actorId: true,
  type: true,
  videoId: true,
  commentId: true,
  commentText: true,
  readAt: true,
  createdAt: true,
} as const;

// Table notifications. Les index uniques partiels (migration notifications) empêchent les doublons
// de like, republication et follow ; une contrainte CHECK refuse une notification adressée à son auteur.
@Injectable()
export class PrismaNotificationRepository extends NotificationRepository {
  constructor(private readonly prisma: PrismaService) {
    super();
  }

  // `skipDuplicates` (ON CONFLICT DO NOTHING) : un second like ne crée pas de seconde notification,
  // et `createManyAndReturn` ne renvoie alors aucune ligne.
  async add(event: ActivityEvent): Promise<Notification | null> {
    const [created] = await this.prisma.notification.createManyAndReturn({
      data: [
        {
          userId: event.recipientId,
          actorId: event.actorId,
          type: event.type,
          videoId: event.type === 'follow' ? null : event.videoId,
          commentId: event.type === 'comment' ? event.commentId : null,
          commentText: event.type === 'comment' ? event.commentText : null,
        },
      ],
      skipDuplicates: true,
      select: notificationSelect,
    });
    return created ? toNotification(created) : null;
  }

  async remove(activity: RetractableActivity): Promise<boolean> {
    const { count } = await this.prisma.notification.deleteMany({
      where:
        activity.type === 'follow'
          ? { type: 'follow', actorId: activity.actorId, userId: activity.recipientId }
          : { type: activity.type, actorId: activity.actorId, videoId: activity.videoId },
    });
    return count > 0;
  }

  async removeBetween(userId: string, otherId: string): Promise<string[]> {
    const where = { OR: [{ userId, actorId: otherId }, { userId: otherId, actorId: userId }] };
    const recipients = await this.prisma.notification.findMany({ where, distinct: ['userId'], select: { userId: true } });
    await this.prisma.notification.deleteMany({ where });
    return recipients.map((r) => r.userId);
  }

  async listForRecipient(recipientId: string, beforeId: string | null, limit: number): Promise<Notification[]> {
    const rows = await this.prisma.notification.findMany({
      where: { userId: recipientId, ...(beforeId ? { id: { lt: beforeId } } : {}) },
      orderBy: { id: 'desc' },
      take: limit,
      select: notificationSelect,
    });
    return rows.map(toNotification);
  }

  countUnread(recipientId: string): Promise<number> {
    return this.prisma.notification.count({ where: { userId: recipientId, readAt: null } });
  }

  async markRead(recipientId: string, upToId: string | null, readAt: Date): Promise<void> {
    await this.prisma.notification.updateMany({
      where: { userId: recipientId, readAt: null, ...(upToId ? { id: { lte: upToId } } : {}) },
      data: { readAt },
    });
  }
}

// La colonne `user_id` est le destinataire.
function toNotification({ userId, ...rest }: Omit<Notification, 'recipientId'> & { userId: string }): Notification {
  return { ...rest, recipientId: userId };
}
