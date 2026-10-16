import { randomUUID } from 'node:crypto';
import type { InMemoryUserRepository } from '../../users/infrastructure/in-memory-user.repository';
import type { InMemoryVideoRepository } from '../../videos/infrastructure/in-memory-video.repository';
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
import { InteractionRepository } from '../domain/interaction.repository';

const COUNTERS = { like: 'likesCount', favorite: 'favoritesCount', repost: 'repostsCount' } as const;

// Adaptateur en mémoire pour les tests. Reproduit les triggers de compteurs de la base
// en ajustant les dépôts en mémoire de `videos` et `users`.
export class InMemoryInteractionRepository extends InteractionRepository {
  // Clés `compte:vidéo` → date de l'action.
  readonly reactions = { like: new Map<string, Date>(), favorite: new Map<string, Date>(), repost: new Map<string, Date>() };
  // Clés `abonné:suivi` → date du follow.
  readonly follows = new Map<string, Date>();
  // Historique de visionnage : clés `compte:vidéo` → date du dernier visionnage.
  readonly views = new Map<string, Date>();
  // Clés `bloqueur:bloqué`, dans l'ordre des blocages.
  readonly blocks: string[] = [];
  readonly comments = new Map<string, Comment>();
  // J'aime de commentaires : « userId:commentId » (ADR-060).
  readonly commentLikes = new Set<string>();
  private sequence = 0;

  constructor(
    private readonly videos: InMemoryVideoRepository,
    private readonly users: InMemoryUserRepository,
  ) {
    super();
  }

  async addReaction(kind: VideoReaction, userId: string, videoId: string): Promise<void> {
    const key = `${userId}:${videoId}`;
    if (this.reactions[kind].has(key)) return;
    // Dates strictement croissantes, pour un ordre déterministe dans les tests.
    this.reactions[kind].set(key, new Date(Date.UTC(2026, 0, 1) + ++this.sequence * 1000));
    this.videos.adjustCounter(videoId, COUNTERS[kind], 1);
  }

  async removeReaction(kind: VideoReaction, userId: string, videoId: string): Promise<void> {
    if (this.reactions[kind].delete(`${userId}:${videoId}`)) this.videos.adjustCounter(videoId, COUNTERS[kind], -1);
  }

  async listReactions(kind: VideoReaction, userId: string, after: ReactionPosition | null, limit: number): Promise<ReactionPosition[]> {
    return [...this.reactions[kind].entries()]
      .flatMap(([key, reactedAt]) => {
        const [reactorId, videoId] = key.split(':') as [string, string];
        return reactorId === userId ? [{ videoId, reactedAt }] : [];
      })
      .sort(compareReactionsDesc)
      .filter((entry) => !after || compareReactionsDesc(after, entry) < 0)
      .slice(0, limit);
  }

  async recordView(userId: string, videoId: string): Promise<void> {
    const key = `${userId}:${videoId}`;
    // Reproduit le trigger de la base : +1 vue à la création de la ligne seulement.
    if (!this.views.has(key)) this.videos.adjustCounter(videoId, 'viewsCount', 1);
    this.views.set(key, new Date(Date.UTC(2026, 0, 1) + ++this.sequence * 1000));
  }

  async listViews(userId: string, after: ViewPosition | null, limit: number): Promise<ViewPosition[]> {
    const positions = [...this.views.entries()].flatMap(([key, viewedAt]) => {
      const [viewerId, videoId] = key.split(':') as [string, string];
      return viewerId === userId ? [{ videoId, reactedAt: viewedAt }] : [];
    });
    return positions
      .sort(compareReactionsDesc)
      .filter((entry) => !after || compareReactionsDesc({ videoId: after.videoId, reactedAt: after.viewedAt }, entry) < 0)
      .slice(0, limit)
      .map(({ videoId, reactedAt }) => ({ videoId, viewedAt: reactedAt }));
  }

  async removeView(userId: string, videoId: string): Promise<void> {
    this.views.delete(`${userId}:${videoId}`);
  }

  async clearViews(userId: string): Promise<void> {
    for (const key of [...this.views.keys()]) if (key.startsWith(`${userId}:`)) this.views.delete(key);
  }

  async follow(followerId: string, followingId: string): Promise<boolean> {
    const key = `${followerId}:${followingId}`;
    if (this.follows.has(key)) return false;
    // Dates strictement croissantes, pour un ordre déterministe dans les tests.
    this.follows.set(key, new Date(Date.UTC(2026, 0, 1) + ++this.sequence * 1000));
    this.users.adjustCounter(followingId, 'followersCount', 1);
    this.users.adjustCounter(followerId, 'followingCount', 1);
    return true;
  }

  async unfollow(followerId: string, followingId: string): Promise<boolean> {
    if (!this.follows.delete(`${followerId}:${followingId}`)) return false;
    this.users.adjustCounter(followingId, 'followersCount', -1);
    this.users.adjustCounter(followerId, 'followingCount', -1);
    return true;
  }

  async listFollows(direction: FollowDirection, userId: string, after: FollowPosition | null, limit: number): Promise<FollowPosition[]> {
    return [...this.follows.entries()]
      .flatMap(([key, followedAt]) => {
        const [followerId, followingId] = key.split(':') as [string, string];
        if (direction === 'followers' && followingId === userId) return [{ userId: followerId, followedAt }];
        if (direction === 'following' && followerId === userId) return [{ userId: followingId, followedAt }];
        return [];
      })
      .sort(compareFollowsDesc)
      .filter((entry) => !after || compareFollowsDesc(after, entry) < 0)
      .slice(0, limit);
  }

  async listFollowerIds(userId: string): Promise<string[]> {
    return [...this.follows.keys()].flatMap((key) => {
      const [followerId, followingId] = key.split(':') as [string, string];
      return followingId === userId ? [followerId] : [];
    });
  }

  async listFollowingIds(userId: string): Promise<string[]> {
    return [...this.follows.keys()].flatMap((key) => {
      const [followerId, followingId] = key.split(':') as [string, string];
      return followerId === userId ? [followingId] : [];
    });
  }

  async findFollowRelations(userId: string, otherIds: string[]): Promise<FollowRelations> {
    return {
      following: new Set(otherIds.filter((id) => this.follows.has(`${userId}:${id}`))),
      followedBy: new Set(otherIds.filter((id) => this.follows.has(`${id}:${userId}`))),
    };
  }

  async createComment(comment: { videoId: string; userId: string; content: string; parentId: string | null }): Promise<Comment> {
    // Identifiants croissants, comme les UUID v7 de la base.
    const id = `${String(++this.sequence).padStart(8, '0')}-${randomUUID()}`;
    const created: Comment = { ...comment, id, repliesCount: 0, likesCount: 0, createdAt: new Date() };
    this.comments.set(id, created);
    this.videos.adjustCounter(comment.videoId, 'commentsCount', 1);
    if (comment.parentId) this.adjustComment(comment.parentId, 'repliesCount', 1);
    return created;
  }

  // Comme les triggers de la migration comment_threads.
  private adjustComment(id: string, counter: 'repliesCount' | 'likesCount', delta: number): void {
    const comment = this.comments.get(id);
    if (comment) this.comments.set(id, { ...comment, [counter]: Math.max(0, comment[counter] + delta) });
  }

  async findComment(id: string): Promise<Comment | null> {
    return this.comments.get(id) ?? null;
  }

  async findCommentsByIds(ids: string[]): Promise<Comment[]> {
    return ids.flatMap((id) => this.comments.get(id) ?? []);
  }

  // Avec ses réponses et les j'aime (cascade).
  async deleteComment(id: string): Promise<void> {
    const comment = this.comments.get(id);
    if (!comment) return;
    for (const reply of [...this.comments.values()].filter((c) => c.parentId === id)) await this.deleteComment(reply.id);
    for (const key of [...this.commentLikes].filter((k) => k.endsWith(`:${id}`))) this.commentLikes.delete(key);
    if (this.comments.delete(id)) this.videos.adjustCounter(comment.videoId, 'commentsCount', -1);
    if (comment.parentId) this.adjustComment(comment.parentId, 'repliesCount', -1);
  }

  async listComments(videoId: string, beforeId: string | null, limit: number): Promise<Comment[]> {
    return [...this.comments.values()]
      .filter((c) => c.videoId === videoId && c.parentId === null && (!beforeId || c.id < beforeId))
      .sort((a, b) => (a.id < b.id ? 1 : -1))
      .slice(0, limit);
  }

  async listReplies(parentId: string, afterId: string | null, limit: number): Promise<Comment[]> {
    return [...this.comments.values()]
      .filter((c) => c.parentId === parentId && (!afterId || c.id > afterId))
      .sort((a, b) => (a.id < b.id ? -1 : 1))
      .slice(0, limit);
  }

  async listReplyIds(parentId: string): Promise<string[]> {
    return [...this.comments.values()].filter((c) => c.parentId === parentId).map((c) => c.id);
  }

  async likeComment(userId: string, commentId: string): Promise<boolean> {
    const key = `${userId}:${commentId}`;
    if (!this.comments.has(commentId) || this.commentLikes.has(key)) return false;
    this.commentLikes.add(key);
    this.adjustComment(commentId, 'likesCount', 1);
    return true;
  }

  async unlikeComment(userId: string, commentId: string): Promise<boolean> {
    if (!this.commentLikes.delete(`${userId}:${commentId}`)) return false;
    this.adjustComment(commentId, 'likesCount', -1);
    return true;
  }

  async findLikedComments(userId: string, commentIds: string[]): Promise<Set<string>> {
    return new Set(commentIds.filter((id) => this.commentLikes.has(`${userId}:${id}`)));
  }

  async listUserComments(userId: string, beforeId: string | null, limit: number): Promise<Comment[]> {
    return [...this.comments.values()]
      .filter((c) => c.userId === userId && (!beforeId || c.id < beforeId))
      .sort((a, b) => (a.id < b.id ? 1 : -1))
      .slice(0, limit);
  }

  async findComments(filter: CommentFilter, beforeId: string | null, limit: number): Promise<Comment[]> {
    return [...this.comments.values()]
      .filter((c) => (!filter.videoId || c.videoId === filter.videoId) && (!filter.userId || c.userId === filter.userId))
      .filter((c) => !beforeId || c.id < beforeId)
      .sort((a, b) => (a.id < b.id ? 1 : -1))
      .slice(0, limit);
  }

  async countComments(createdSince: Date | null): Promise<number> {
    return [...this.comments.values()].filter((c) => !createdSince || c.createdAt >= createdSince).length;
  }

  async block(blockerId: string, blockedId: string): Promise<boolean> {
    const key = `${blockerId}:${blockedId}`;
    if (!this.blocks.includes(key)) this.blocks.push(key);
    const first = await this.unfollow(blockerId, blockedId);
    const second = await this.unfollow(blockedId, blockerId);
    return first || second;
  }

  async unblock(blockerId: string, blockedId: string): Promise<void> {
    const index = this.blocks.indexOf(`${blockerId}:${blockedId}`);
    if (index >= 0) this.blocks.splice(index, 1);
  }

  async isBlockedBetween(userId: string, otherId: string): Promise<boolean> {
    return this.blocks.includes(`${userId}:${otherId}`) || this.blocks.includes(`${otherId}:${userId}`);
  }

  async findBlocks(userId: string, otherIds: string[]): Promise<BlockRelations> {
    return {
      blockedByMe: new Set(otherIds.filter((id) => this.blocks.includes(`${userId}:${id}`))),
      blockedMe: new Set(otherIds.filter((id) => this.blocks.includes(`${id}:${userId}`))),
    };
  }

  async findBlockedEitherWay(userId: string): Promise<Set<string>> {
    return new Set(
      this.blocks.flatMap((key) => {
        const [blockerId, blockedId] = key.split(':') as [string, string];
        if (blockerId === userId) return [blockedId];
        return blockedId === userId ? [blockerId] : [];
      }),
    );
  }

  async listBlocked(blockerId: string): Promise<string[]> {
    return this.blocks
      .filter((key) => key.startsWith(`${blockerId}:`))
      .map((key) => key.split(':')[1])
      .reverse();
  }

  async findSuggestionCandidates(userId: string, excludedIds: string[], limit: number): Promise<SuggestionCandidate[]> {
    const following = new Set(await this.listFollowingIds(userId));
    const fans = new Set(await this.listFollowerIds(userId));
    // Ordre d'insertion des follows = ordre du temps : les plus récents en dernier.
    const via = new Map<string, string[]>();
    for (const key of this.follows.keys()) {
      const [followerId, followingId] = key.split(':') as [string, string];
      if (following.has(followerId)) via.set(followingId, [followerId, ...(via.get(followingId) ?? [])]);
    }
    const excluded = new Set([userId, ...following, ...excludedIds]);
    return [...new Set([...via.keys(), ...fans])]
      .filter((id) => !excluded.has(id))
      .map((id) => ({
        userId: id,
        followsMe: fans.has(id),
        followedByIds: (via.get(id) ?? []).slice(0, SUGGESTION_FOLLOWERS_SHOWN),
        followedByCount: via.get(id)?.length ?? 0,
      }))
      .sort((a, b) => Number(b.followsMe) - Number(a.followsMe) || b.followedByCount - a.followedByCount || (a.userId < b.userId ? -1 : 1))
      .slice(0, limit);
  }

  async findMutualFollows(userId: string, userIds: string[]): Promise<Set<string>> {
    return new Set(userIds.filter((id) => this.follows.has(`${userId}:${id}`) && this.follows.has(`${id}:${userId}`)));
  }

  async findViewerInteractions(userId: string, videoIds: string[], authorIds: string[]): Promise<ViewerInteractions> {
    const among = (set: { has(key: string): boolean }, ids: string[]) => new Set(ids.filter((id) => set.has(`${userId}:${id}`)));
    return {
      likedVideoIds: among(this.reactions.like, videoIds),
      favoritedVideoIds: among(this.reactions.favorite, videoIds),
      repostedVideoIds: among(this.reactions.repost, videoIds),
      followedUserIds: among(this.follows, authorIds),
    };
  }
}

// Du plus récent au plus ancien, puis par identifiant décroissant (même ordre que la base).
function compareFollowsDesc(a: FollowPosition, b: FollowPosition): number {
  const byDate = b.followedAt.getTime() - a.followedAt.getTime();
  if (byDate !== 0) return byDate;
  return a.userId < b.userId ? 1 : a.userId > b.userId ? -1 : 0;
}

function compareReactionsDesc(a: ReactionPosition, b: ReactionPosition): number {
  const byDate = b.reactedAt.getTime() - a.reactedAt.getTime();
  if (byDate !== 0) return byDate;
  return a.videoId < b.videoId ? 1 : a.videoId > b.videoId ? -1 : 0;
}
