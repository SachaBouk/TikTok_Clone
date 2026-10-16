import { Injectable } from '@nestjs/common';
import { Prisma } from '../../../generated/prisma/client';
import { PrismaService } from '../../../database/prisma.service';
import type {
  BlockRelations,
  Comment,
  CommentFilter,
  FollowDirection,
  FollowPosition,
  FollowRelations,
  ReactionPosition,
  SuggestionCandidate,
  VideoReaction,
  ViewerInteractions,
  ViewPosition,
} from '../domain/interaction';
import { SUGGESTION_FOLLOWERS_SHOWN } from '../domain/interaction';
import { VideoNotAvailableError } from '../domain/interaction.errors';
import { InteractionRepository } from '../domain/interaction.repository';

const commentSelect = {
  id: true,
  videoId: true,
  userId: true,
  parentId: true,
  content: true,
  repliesCount: true,
  likesCount: true,
  createdAt: true,
} as const;

// Tables likes, favorites, reposts, comments, follows. Les triggers de la base mettent les compteurs à jour.
@Injectable()
export class PrismaInteractionRepository extends InteractionRepository {
  constructor(private readonly prisma: PrismaService) {
    super();
  }

  // `skipDuplicates` (ON CONFLICT DO NOTHING) : un second like ne crée rien, donc ne compte pas deux fois.
  async addReaction(kind: VideoReaction, userId: string, videoId: string): Promise<void> {
    await withVideoCheck(videoId, () => this.reactionTable(kind).createMany({ data: [{ userId, videoId }], skipDuplicates: true }));
  }

  async removeReaction(kind: VideoReaction, userId: string, videoId: string): Promise<void> {
    await this.reactionTable(kind).deleteMany({ where: { userId, videoId } });
  }

  // Pagination par clé (created_at, video_id), sur les index (user_id, created_at) des trois tables.
  async listReactions(kind: VideoReaction, userId: string, after: ReactionPosition | null, limit: number): Promise<ReactionPosition[]> {
    const rows = await this.reactionTable(kind).findMany({
      where: {
        userId,
        ...(after ? { OR: [{ createdAt: { lt: after.reactedAt } }, { createdAt: after.reactedAt, videoId: { lt: after.videoId } }] } : {}),
      },
      orderBy: [{ createdAt: 'desc' }, { videoId: 'desc' }],
      take: limit,
      select: { videoId: true, createdAt: true },
    });
    return rows.map((row) => ({ videoId: row.videoId, reactedAt: row.createdAt }));
  }

  // INSERT … ON CONFLICT DO UPDATE : le trigger AFTER INSERT (migration view_history) ne se déclenche que pour
  // une ligne réellement créée, donc views_count ne compte chaque compte qu'une fois.
  async recordView(userId: string, videoId: string): Promise<void> {
    try {
      await this.prisma.$executeRaw`
        INSERT INTO view_history (user_id, video_id, viewed_at)
        VALUES (${userId}::uuid, ${videoId}::uuid, now())
        ON CONFLICT (user_id, video_id) DO UPDATE SET viewed_at = EXCLUDED.viewed_at`;
    } catch (error) {
      // Vidéo supprimée entre la vérification du service et l'écriture : clé étrangère (23503).
      if (isForeignKeyViolation(error)) throw new VideoNotAvailableError(videoId);
      throw error;
    }
  }

  // Pagination par clé (viewed_at, video_id), sur l'index (user_id, viewed_at).
  async listViews(userId: string, after: ViewPosition | null, limit: number): Promise<ViewPosition[]> {
    const rows = await this.prisma.viewHistory.findMany({
      where: {
        userId,
        ...(after ? { OR: [{ viewedAt: { lt: after.viewedAt } }, { viewedAt: after.viewedAt, videoId: { lt: after.videoId } }] } : {}),
      },
      orderBy: [{ viewedAt: 'desc' }, { videoId: 'desc' }],
      take: limit,
      select: { videoId: true, viewedAt: true },
    });
    return rows;
  }

  async removeView(userId: string, videoId: string): Promise<void> {
    await this.prisma.viewHistory.deleteMany({ where: { userId, videoId } });
  }

  async clearViews(userId: string): Promise<void> {
    await this.prisma.viewHistory.deleteMany({ where: { userId } });
  }

  async follow(followerId: string, followingId: string): Promise<boolean> {
    const { count } = await this.prisma.follow.createMany({ data: [{ followerId, followingId }], skipDuplicates: true });
    return count > 0;
  }

  async unfollow(followerId: string, followingId: string): Promise<boolean> {
    const { count } = await this.prisma.follow.deleteMany({ where: { followerId, followingId } });
    return count > 0;
  }

  // Pagination par clé (date du follow, identifiant du compte), sur les index (following_id, created_at)
  // et (follower_id, created_at).
  async listFollows(direction: FollowDirection, userId: string, after: FollowPosition | null, limit: number): Promise<FollowPosition[]> {
    // Abonnés : les lignes où `userId` est suivi, le compte listé est l'abonné. Abonnements : l'inverse.
    const [own, other] = direction === 'followers' ? (['followingId', 'followerId'] as const) : (['followerId', 'followingId'] as const);
    const rows = await this.prisma.follow.findMany({
      where: {
        [own]: userId,
        ...(after ? { OR: [{ createdAt: { lt: after.followedAt } }, { createdAt: after.followedAt, [other]: { lt: after.userId } }] } : {}),
      },
      orderBy: [{ createdAt: 'desc' }, { [other]: 'desc' }],
      take: limit,
      select: { followerId: true, followingId: true, createdAt: true },
    });
    return rows.map((row) => ({ userId: row[other], followedAt: row.createdAt }));
  }

  // Clé primaire (follower_id, following_id) : lecture d'index seule.
  async listFollowingIds(userId: string): Promise<string[]> {
    const rows = await this.prisma.follow.findMany({ where: { followerId: userId }, select: { followingId: true } });
    return rows.map((row) => row.followingId);
  }

  // Index (following_id, created_at).
  async listFollowerIds(userId: string): Promise<string[]> {
    const rows = await this.prisma.follow.findMany({ where: { followingId: userId }, select: { followerId: true } });
    return rows.map((row) => row.followerId);
  }

  async findFollowRelations(userId: string, otherIds: string[]): Promise<FollowRelations> {
    if (otherIds.length === 0) return { following: new Set(), followedBy: new Set() };
    const rows = await this.prisma.follow.findMany({
      where: {
        OR: [
          { followerId: userId, followingId: { in: otherIds } },
          { followingId: userId, followerId: { in: otherIds } },
        ],
      },
      select: { followerId: true, followingId: true },
    });
    return {
      following: new Set(rows.filter((r) => r.followerId === userId).map((r) => r.followingId)),
      followedBy: new Set(rows.filter((r) => r.followingId === userId).map((r) => r.followerId)),
    };
  }

  createComment(comment: { videoId: string; userId: string; content: string; parentId: string | null }): Promise<Comment> {
    return withVideoCheck(comment.videoId, () => this.prisma.comment.create({ data: comment, select: commentSelect }));
  }

  findComment(id: string): Promise<Comment | null> {
    return this.prisma.comment.findUnique({ where: { id }, select: commentSelect });
  }

  async findCommentsByIds(ids: string[]): Promise<Comment[]> {
    if (ids.length === 0) return [];
    return this.prisma.comment.findMany({ where: { id: { in: ids } }, select: commentSelect });
  }

  async deleteComment(id: string): Promise<void> {
    await this.prisma.comment.deleteMany({ where: { id } });
  }

  listComments(videoId: string, beforeId: string | null, limit: number): Promise<Comment[]> {
    return this.prisma.comment.findMany({
      where: { videoId, parentId: null, ...(beforeId ? { id: { lt: beforeId } } : {}) },
      orderBy: { id: 'desc' },
      take: limit,
      select: commentSelect,
    });
  }

  // Index (parent_id, comment_id).
  listReplies(parentId: string, afterId: string | null, limit: number): Promise<Comment[]> {
    return this.prisma.comment.findMany({
      where: { parentId, ...(afterId ? { id: { gt: afterId } } : {}) },
      orderBy: { id: 'asc' },
      take: limit,
      select: commentSelect,
    });
  }

  async listReplyIds(parentId: string): Promise<string[]> {
    const rows = await this.prisma.comment.findMany({ where: { parentId }, select: { id: true } });
    return rows.map((row) => row.id);
  }

  // `skipDuplicates` : un second j'aime ne crée rien (le trigger ne compte que les lignes insérées). Un commentaire
  // supprimé entre-temps fait échouer la clé étrangère : rien n'est ajouté.
  async likeComment(userId: string, commentId: string): Promise<boolean> {
    try {
      const { count } = await this.prisma.commentLike.createMany({ data: [{ userId, commentId }], skipDuplicates: true });
      return count > 0;
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2003') return false;
      throw error;
    }
  }

  async unlikeComment(userId: string, commentId: string): Promise<boolean> {
    const { count } = await this.prisma.commentLike.deleteMany({ where: { userId, commentId } });
    return count > 0;
  }

  async findLikedComments(userId: string, commentIds: string[]): Promise<Set<string>> {
    if (commentIds.length === 0) return new Set();
    const rows = await this.prisma.commentLike.findMany({ where: { userId, commentId: { in: commentIds } }, select: { commentId: true } });
    return new Set(rows.map((row) => row.commentId));
  }

  // Filtre sur l'index (user_id, created_at) ; l'identifiant UUID v7 suit l'ordre de création.
  listUserComments(userId: string, beforeId: string | null, limit: number): Promise<Comment[]> {
    return this.prisma.comment.findMany({
      where: { userId, ...(beforeId ? { id: { lt: beforeId } } : {}) },
      orderBy: { id: 'desc' },
      take: limit,
      select: commentSelect,
    });
  }

  findComments(filter: CommentFilter, beforeId: string | null, limit: number): Promise<Comment[]> {
    return this.prisma.comment.findMany({
      where: { videoId: filter.videoId, userId: filter.userId, ...(beforeId ? { id: { lt: beforeId } } : {}) },
      orderBy: { id: 'desc' },
      take: limit,
      select: commentSelect,
    });
  }

  countComments(createdSince: Date | null): Promise<number> {
    return this.prisma.comment.count({ where: createdSince ? { createdAt: { gte: createdSince } } : undefined });
  }

  async block(blockerId: string, blockedId: string): Promise<boolean> {
    const [, unfollowed] = await this.prisma.$transaction([
      this.prisma.block.createMany({ data: [{ blockerId, blockedId }], skipDuplicates: true }),
      this.prisma.follow.deleteMany({
        where: {
          OR: [
            { followerId: blockerId, followingId: blockedId },
            { followerId: blockedId, followingId: blockerId },
          ],
        },
      }),
    ]);
    return unfollowed.count > 0;
  }

  async unblock(blockerId: string, blockedId: string): Promise<void> {
    await this.prisma.block.deleteMany({ where: { blockerId, blockedId } });
  }

  async isBlockedBetween(userId: string, otherId: string): Promise<boolean> {
    const count = await this.prisma.block.count({
      where: {
        OR: [
          { blockerId: userId, blockedId: otherId },
          { blockerId: otherId, blockedId: userId },
        ],
      },
    });
    return count > 0;
  }

  async findBlocks(userId: string, otherIds: string[]): Promise<BlockRelations> {
    const rows = await this.prisma.block.findMany({
      where: {
        OR: [
          { blockerId: userId, blockedId: { in: otherIds } },
          { blockedId: userId, blockerId: { in: otherIds } },
        ],
      },
      select: { blockerId: true, blockedId: true },
    });
    return {
      blockedByMe: new Set(rows.filter((r) => r.blockerId === userId).map((r) => r.blockedId)),
      blockedMe: new Set(rows.filter((r) => r.blockedId === userId).map((r) => r.blockerId)),
    };
  }

  // Deux lectures sur les index de la table (clé primaire et `blocked_id`) : un compte en bloque peu.
  async findBlockedEitherWay(userId: string): Promise<Set<string>> {
    const rows = await this.prisma.block.findMany({
      where: { OR: [{ blockerId: userId }, { blockedId: userId }] },
      select: { blockerId: true, blockedId: true },
    });
    return new Set(rows.map((r) => (r.blockerId === userId ? r.blockedId : r.blockerId)));
  }

  async listBlocked(blockerId: string): Promise<string[]> {
    const rows = await this.prisma.block.findMany({ where: { blockerId }, orderBy: { createdAt: 'desc' }, select: { blockedId: true } });
    return rows.map((r) => r.blockedId);
  }

  // Une requête : ceux que l'on suit (`mine`), les comptes qu'ils suivent (`via`) et ses abonnés (`fans`), regroupés par
  // candidat. Index `follows(follower_id)` (clé) et `(following_id, created_at)`.
  async findSuggestionCandidates(userId: string, excludedIds: string[], limit: number): Promise<SuggestionCandidate[]> {
    const rows = await this.prisma.$queryRaw<{ user_id: string; follows_me: boolean; via_ids: string[] | null; via_count: number }[]>`
      WITH mine AS (
        SELECT following_id FROM follows WHERE follower_id = ${userId}::uuid
      ), via AS (
        SELECT f.following_id AS candidate, f.follower_id AS via_id, f.created_at
        FROM follows f JOIN mine m ON f.follower_id = m.following_id
      ), fans AS (
        SELECT follower_id AS candidate FROM follows WHERE following_id = ${userId}::uuid
      ), candidates AS (
        SELECT candidate FROM via UNION SELECT candidate FROM fans
      )
      SELECT c.candidate::text AS user_id,
             EXISTS (SELECT 1 FROM fans WHERE fans.candidate = c.candidate) AS follows_me,
             (SELECT (array_agg(v.via_id::text ORDER BY v.created_at DESC))[1:${SUGGESTION_FOLLOWERS_SHOWN}] FROM via v WHERE v.candidate = c.candidate) AS via_ids,
             (SELECT count(*)::int FROM via v WHERE v.candidate = c.candidate) AS via_count
      FROM candidates c
      WHERE c.candidate <> ${userId}::uuid
        AND c.candidate NOT IN (SELECT following_id FROM mine)
        AND NOT (c.candidate = ANY(${excludedIds}::uuid[]))
      ORDER BY follows_me DESC, via_count DESC, c.candidate
      LIMIT ${limit}`;
    return rows.map((r) => ({ userId: r.user_id, followsMe: r.follows_me, followedByIds: r.via_ids ?? [], followedByCount: r.via_count }));
  }

  async findMutualFollows(userId: string, userIds: string[]): Promise<Set<string>> {
    const rows = await this.prisma.follow.findMany({
      where: { followerId: userId, followingId: { in: userIds }, following: { following: { some: { followingId: userId } } } },
      select: { followingId: true },
    });
    return new Set(rows.map((r) => r.followingId));
  }

  async findViewerInteractions(userId: string, videoIds: string[], authorIds: string[]): Promise<ViewerInteractions> {
    const onVideos = { userId, videoId: { in: videoIds } };
    const [likes, favorites, reposts, follows] = await Promise.all([
      this.prisma.like.findMany({ where: onVideos, select: { videoId: true } }),
      this.prisma.favorite.findMany({ where: onVideos, select: { videoId: true } }),
      this.prisma.repost.findMany({ where: onVideos, select: { videoId: true } }),
      this.prisma.follow.findMany({ where: { followerId: userId, followingId: { in: authorIds } }, select: { followingId: true } }),
    ]);
    return {
      likedVideoIds: new Set(likes.map((r) => r.videoId)),
      favoritedVideoIds: new Set(favorites.map((r) => r.videoId)),
      repostedVideoIds: new Set(reposts.map((r) => r.videoId)),
      followedUserIds: new Set(follows.map((r) => r.followingId)),
    };
  }

  private reactionTable(kind: VideoReaction) {
    // Les trois délégués ont la même forme (clé composite userId + videoId) ; l'union de types Prisma
    // n'est pas appelable directement, d'où ce typage commun.
    const tables = { like: this.prisma.like, favorite: this.prisma.favorite, repost: this.prisma.repost };
    return tables[kind] as unknown as typeof this.prisma.like;
  }
}

// Vidéo supprimée entre la vérification du service et l'écriture : la clé étrangère refuse (P2003).
async function withVideoCheck<T>(videoId: string, write: () => Promise<T>): Promise<T> {
  try {
    return await write();
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2003') throw new VideoNotAvailableError(videoId);
    throw error;
  }
}

// Erreur de clé étrangère d'une requête SQL brute (P2010) ou du client (P2003).
function isForeignKeyViolation(error: unknown): boolean {
  if (!(error instanceof Prisma.PrismaClientKnownRequestError)) return false;
  return error.code === 'P2003' || (error.code === 'P2010' && JSON.stringify(error.meta ?? {}).includes('23503'));
}
