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
  NotificationType,
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
  giftCode: true,
  giftAmount: true,
  liveId: true,
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
          videoId: event.type === 'follow' || event.type === 'live' ? null : event.videoId,
          commentId: 'commentId' in event ? event.commentId : null,
          commentText: 'commentText' in event ? event.commentText : null,
          giftCode: event.type === 'gift' ? event.giftCode : null,
          giftAmount: event.type === 'gift' ? event.giftAmount : null,
          liveId: event.type === 'live' ? event.liveId : null,
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
    switch (activity.type) {
      case 'follow':
        return this.removeWhere({ type: 'follow', actorId: activity.actorId, userId: activity.recipientId });
      case 'commentLike':
        return this.removeWhere({ type: 'commentLike', actorId: activity.actorId, commentId: activity.commentId });
      default:
        return this.removeWhere({ type: activity.type, actorId: activity.actorId, videoId: activity.videoId });
    }
  }

  removeBetween(userId: string, otherId: string): Promise<Notification[]> {
    return this.removeWhere({
      OR: [
        { userId, actorId: otherId },
        { userId: otherId, actorId: userId },
      ],
    });
  }

  async removeForComments(commentIds: string[]): Promise<Notification[]> {
    if (commentIds.length === 0) return [];
    return this.removeWhere({ commentId: { in: commentIds } });
  }

  removeForVideo(videoId: string): Promise<Notification[]> {
    return this.removeWhere({ videoId });
  }

  removeByActor(actorId: string): Promise<Notification[]> {
    return this.removeWhere({ actorId });
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
        ...(filter.commentId ? { commentId: filter.commentId } : {}),
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
  listGroups(
    recipientId: string,
    beforeId: string | null,
    limit: number,
    excludedActorIds: string[],
    types?: NotificationType[],
  ): Promise<NotificationGroup[]> {
    const before = beforeId ? Prisma.sql`WHERE latest_id < ${beforeId}::uuid` : Prisma.empty;
    const only = types?.length ? Prisma.sql`AND type::text = ANY(${types.map(dbType)}::text[])` : Prisma.empty;
    return this.groups(recipientId, only, before, limit, excludedActorIds);
  }

  // Mêmes groupes, restreints aux notifications de `filters` avant le regroupement.
  findGroups(recipientId: string, filters: NotificationFilter[], excludedActorIds: string[]): Promise<NotificationGroup[]> {
    if (filters.length === 0) return Promise.resolve([]);
    // `type` en valeur de la base (`comment_like`), comme dans `groups`.
    const conditions = filters.map((filter) => {
      const type = Prisma.sql`type = ${dbType(filter.type)}::notification_type`;
      if (filter.videoId) return Prisma.sql`(${type} AND video_id = ${filter.videoId}::uuid)`;
      if (filter.commentId) return Prisma.sql`(${type} AND comment_id = ${filter.commentId}::uuid)`;
      return type;
    });
    return this.groups(recipientId, Prisma.sql`AND (${Prisma.join(conditions, ' OR ')})`, Prisma.empty, filters.length, excludedActorIds);
  }

  private async groups(
    recipientId: string,
    only: Prisma.Sql,
    before: Prisma.Sql,
    limit: number,
    excludedActorIds: string[],
  ): Promise<NotificationGroup[]> {
    // Sans auteur (modération) : jamais exclue (`actor_id <> ALL(…)` vaudrait NULL).
    const excluded = excludedActorIds.length ? Prisma.sql`AND (actor_id IS NULL OR actor_id <> ALL(${excludedActorIds}::uuid[]))` : Prisma.empty;
    // Clé de groupe : like, republication et cadeau par vidéo, tous les follows, j'aime de commentaire par commentaire, le reste seul. Auteurs **distincts**, du
    // plus récent au plus ancien (un compte peut envoyer plusieurs cadeaux sur la même vidéo, ADR-050).
    const rows = await this.prisma.$queryRaw<{ latest_id: string; count: number; unread: boolean; actor_ids: string[] | null }[]>`
      WITH base AS (
        SELECT notification_id, actor_id, read_at,
               type::text || ':' || CASE WHEN type IN ('like', 'repost', 'gift') THEN video_id::text
                                         WHEN type = 'follow' THEN ''
                                         WHEN type = 'live' THEN live_id::text
                                         WHEN type = 'comment_like' THEN comment_id::text
                                         ELSE notification_id::text END AS group_key
        FROM notifications
        WHERE user_id = ${recipientId}::uuid ${excluded} ${only}
      ), grouped AS (
        SELECT group_key, max(notification_id::text)::uuid AS latest_id, count(*)::int AS count, bool_or(read_at IS NULL) AS unread
        FROM base GROUP BY group_key
      ), actors AS (
        SELECT group_key, (array_agg(actor_id ORDER BY last_id DESC))[1:${GROUP_ACTORS_SHOWN}] AS actor_ids
        FROM (SELECT group_key, actor_id::text AS actor_id, max(notification_id::text) AS last_id FROM base WHERE actor_id IS NOT NULL GROUP BY group_key, actor_id) per_actor
        GROUP BY group_key
      )
      SELECT latest_id::text AS latest_id, count, unread, actor_ids FROM grouped LEFT JOIN actors USING (group_key)
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
    gift: row.giftCode && row.giftAmount !== null ? { code: row.giftCode, amount: row.giftAmount } : null,
    liveId: row.liveId,
    readAt: row.readAt,
    createdAt: row.createdAt,
  };
}

// Valeur de l'enum dans la base (`@map` du schéma) : `comment_like` pour `commentLike`. Les filtres SQL bruts la comparent.
function dbType(type: NotificationType | undefined): string | undefined {
  return type?.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`);
}
