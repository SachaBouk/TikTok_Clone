import { Injectable } from '@nestjs/common';
import { Prisma } from '../../../generated/prisma/client';
import { PrismaService } from '../../../database/prisma.service';
import {
  GROUP_ACTORS_SHOWN,
  type ActivityEvent,
  type ModerationEvent,
  type ModerationOutcome,
  type Notification,
  type NotificationFilter,
  type NotificationGroup,
  type RetractableActivity,
} from '../domain/notification';
import { NotificationRepository } from '../domain/notification.repository';

const notificationSelect = {
  id: true,
  userId: true,
  actorId: true,
  type: true,
  videoId: true,
  commentId: true,
  commentText: true,
  moderationTargetType: true,
  moderationReason: true,
  moderationOutcome: true,
  moderationExcerpt: true,
  readAt: true,
  createdAt: true,
} as const;

type NotificationRow = Prisma.NotificationGetPayload<{ select: typeof notificationSelect }>;

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

  async addModeration(event: ModerationEvent): Promise<Notification> {
    const created = await this.prisma.notification.create({
      data: {
        userId: event.recipientId,
        type: event.type,
        moderationTargetType: event.targetType,
        moderationReason: event.type === 'contentRemoved' ? event.reason : null,
        moderationOutcome: event.type === 'reportResolved' ? event.outcome : null,
        moderationExcerpt: event.excerpt,
      },
      select: notificationSelect,
    });
    return toNotification(created);
  }

  remove(activity: RetractableActivity): Promise<Notification[]> {
    return this.removeWhere(
      activity.type === 'follow'
        ? { type: 'follow', actorId: activity.actorId, userId: activity.recipientId }
        : { type: activity.type, actorId: activity.actorId, videoId: activity.videoId },
    );
  }

  removeBetween(userId: string, otherId: string): Promise<Notification[]> {
    return this.removeWhere({
      OR: [
        { userId, actorId: otherId },
        { userId: otherId, actorId: userId },
      ],
    });
  }

  removeForComment(commentId: string): Promise<Notification[]> {
    return this.removeWhere({ commentId });
  }

  // Lignes lues, puis supprimées par leurs identifiants. Deux retraits simultanés de la même notification (rare : deux
  // appareils) peuvent l'annoncer deux fois ; l'app ignore la seconde annonce (identifiant déjà retiré).
  private async removeWhere(where: Prisma.NotificationWhereInput): Promise<Notification[]> {
    const rows = await this.prisma.notification.findMany({ where, select: notificationSelect });
    if (rows.length === 0) return [];
    await this.prisma.notification.deleteMany({ where: { id: { in: rows.map((row) => row.id) } } });
    return rows.map(toNotification);
  }

  async listForRecipient(
    recipientId: string,
    filter: NotificationFilter,
    beforeId: string | null,
    limit: number,
    excludedActorIds: string[],
  ): Promise<Notification[]> {
    const rows = await this.prisma.notification.findMany({
      where: {
        userId: recipientId,
        ...(excludedActorIds.length ? { OR: [{ actorId: null }, { actorId: { notIn: excludedActorIds } }] } : {}),
        ...(filter.type ? { type: filter.type } : {}),
        ...(filter.videoId ? { videoId: filter.videoId } : {}),
        ...(beforeId ? { id: { lt: beforeId } } : {}),
      },
      orderBy: { id: 'desc' },
      take: limit,
      select: notificationSelect,
    });
    return rows.map(toNotification);
  }

  // Regroupement en SQL, sur les seules notifications du compte (index `user_id`) : une ligne par groupe, avec
  // la notification la plus récente (UUID v7 : l'ordre du texte est l'ordre du temps), le nombre, l'état de
  // lecture et les auteurs les plus récents. Les notifications les plus récentes sont ensuite relues par Prisma.
  async listGroups(recipientId: string, beforeId: string | null, limit: number, excludedActorIds: string[]): Promise<NotificationGroup[]> {
    const before = beforeId ? Prisma.sql`WHERE latest_id < ${beforeId}::uuid` : Prisma.empty;
    // Sans auteur (modération) : jamais exclue (`actor_id <> ALL(…)` vaudrait NULL).
    const excluded = excludedActorIds.length ? Prisma.sql`AND (actor_id IS NULL OR actor_id <> ALL(${excludedActorIds}::uuid[]))` : Prisma.empty;
    const rows = await this.prisma.$queryRaw<{ latest_id: string; count: number; unread: boolean; actor_ids: string[] | null }[]>`
      WITH grouped AS (
        SELECT max(notification_id::text)::uuid AS latest_id,
               count(*)::int AS count,
               bool_or(read_at IS NULL) AS unread,
               (array_agg(actor_id::text ORDER BY notification_id DESC) FILTER (WHERE actor_id IS NOT NULL))[1:${GROUP_ACTORS_SHOWN}] AS actor_ids
        FROM notifications
        WHERE user_id = ${recipientId}::uuid ${excluded}
        GROUP BY type,
                 CASE WHEN type IN ('like', 'repost') THEN video_id END,
                 CASE WHEN type NOT IN ('like', 'repost', 'follow') THEN notification_id END
      )
      SELECT latest_id::text AS latest_id, count, unread, actor_ids FROM grouped
      ${before}
      ORDER BY latest_id DESC
      LIMIT ${limit}`;
    if (rows.length === 0) return [];
    const latest = new Map(
      (await this.prisma.notification.findMany({ where: { id: { in: rows.map((r) => r.latest_id) } }, select: notificationSelect })).map((n) => [
        n.id,
        toNotification(n),
      ]),
    );
    return rows.flatMap((row) => {
      const notification = latest.get(row.latest_id);
      return notification ? [{ latest: notification, count: row.count, unread: row.unread, recentActorIds: row.actor_ids ?? [] }] : [];
    });
  }

  countUnread(recipientId: string, excludedActorIds: string[]): Promise<number> {
    return this.prisma.notification.count({
      where: {
        userId: recipientId,
        readAt: null,
        ...(excludedActorIds.length ? { OR: [{ actorId: null }, { actorId: { notIn: excludedActorIds } }] } : {}),
      },
    });
  }

  async markRead(recipientId: string, upToId: string | null, readAt: Date): Promise<void> {
    await this.prisma.notification.updateMany({
      where: { userId: recipientId, readAt: null, ...(upToId ? { id: { lte: upToId } } : {}) },
      data: { readAt },
    });
  }
}

// La colonne `user_id` est le destinataire ; les colonnes de modération forment `moderation`.
function toNotification(row: NotificationRow): Notification {
  return {
    id: row.id,
    recipientId: row.userId,
    actorId: row.actorId,
    type: row.type,
    videoId: row.videoId,
    commentId: row.commentId,
    commentText: row.commentText,
    moderation: row.moderationTargetType
      ? {
          targetType: row.moderationTargetType,
          reason: row.moderationReason,
          outcome: row.moderationOutcome as ModerationOutcome | null,
          excerpt: row.moderationExcerpt,
        }
      : null,
    readAt: row.readAt,
    createdAt: row.createdAt,
  };
}
