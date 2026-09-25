import type { NotificationsService } from '../../notifications/application/notifications.service';
import type { UsersService } from '../../users/application/users.service';
import type { User } from '../../users/domain/user';
import { UserNotFoundError } from '../../users/domain/user.errors';
import type { VideosService } from '../../videos/application/videos.service';
import type { PublishedVideo } from '../../videos/domain/video';
import { decodeFollowCursor, encodeFollowCursor } from '../domain/follow-cursor';
import type {
  BlockRelations,
  Comment,
  FollowDirection,
  ReactionPosition,
  Relationship,
  VideoReaction,
  ViewerInteractions,
  ViewPosition,
} from '../domain/interaction';
import {
  BlockedError,
  CannotBlockYourselfError,
  CannotFollowYourselfError,
  CommentNotFoundError,
  EmptyCommentError,
  NotCommentAuthorError,
  TargetUserNotFoundError,
  VideoNotAvailableError,
} from '../domain/interaction.errors';
import type { InteractionRepository } from '../domain/interaction.repository';

export interface InteractionState {
  active: boolean;
  count: number;
}

export interface CommentWithAuthor {
  comment: Comment;
  author: User;
}

// Un commentaire de l'historique, avec la vidéo commentée et son auteur.
export interface CommentHistoryItem {
  comment: Comment;
  video: PublishedVideo;
  videoAuthor: User;
}

export interface CommentHistoryPage {
  items: CommentHistoryItem[];
  nextCursor: string | null;
}

export interface CommentPage {
  items: CommentWithAuthor[];
  nextCursor: string | null;
}

export interface FollowItem {
  user: User;
  followedAt: Date;
  // Relation avec le compte connecté ; absente en mode invité.
  viewer?: { following: boolean; followedBy: boolean };
}

export interface FollowPage {
  items: FollowItem[];
  nextCursor: string | null;
}

const REACTION_COUNTERS = {
  like: 'likesCount',
  favorite: 'favoritesCount',
  repost: 'repostsCount',
} as const satisfies Record<VideoReaction, keyof PublishedVideo>;

// Service applicatif des interactions sociales (ADR-003, ADR-016).
// Les vidéos et les comptes sont lus via les services exportés de `videos` et `users` ; les compteurs
// sont mis à jour par les triggers de la base : ce service ne les écrit jamais, il relit la valeur à jour.
// Like, republication, commentaire et follow alimentent le centre d'activité via `notifications`,
// après l'écriture de l'interaction : un PUT rejoué après un échec recrée la notification manquante.
export class InteractionsService {
  constructor(
    private readonly interactions: InteractionRepository,
    private readonly videos: VideosService,
    private readonly users: UsersService,
    private readonly notifications: NotificationsService,
  ) {}

  // Like, favori ou republication (`active`), ou leur retrait. Idempotent. Seulement sur une vidéo publiée.
  // Un favori ne notifie pas l'auteur (pas de type `favorite` dans le centre d'activité, ADR-006).
  async setReaction(userId: string, videoId: string, kind: VideoReaction, active: boolean): Promise<InteractionState> {
    const { userId: authorId } = await this.publishedVideo(videoId);
    // Blocage : ni like ni republication (visibles et notifiés). Le favori, privé, reste possible ;
    // retirer une réaction aussi.
    if (active && kind !== 'favorite') await this.assertNotBlocked(userId, authorId);
    if (active) await this.interactions.addReaction(kind, userId, videoId);
    else await this.interactions.removeReaction(kind, userId, videoId);

    if (kind !== 'favorite') {
      const activity = { type: kind, actorId: userId, recipientId: authorId, videoId };
      if (active) await this.notifications.notify(activity);
      else await this.notifications.retract(activity);
    }

    const video = await this.publishedVideo(videoId);
    return { active, count: video[REACTION_COUNTERS[kind]] };
  }

  // Visionnage d'une vidéo publiée par un compte connecté (l'app l'envoie après ~1 s de lecture) : ajoute la vidéo
  // en tête de son historique. `views_count` ne compte que la première fois pour ce compte (ADR-006, trigger).
  // Ses propres vidéos ne sont ni comptées ni ajoutées à l'historique. Pas de restriction de blocage :
  // voir une vidéo reste possible, comme dans le feed.
  async recordView(userId: string, videoId: string): Promise<void> {
    const video = await this.publishedVideo(videoId);
    if (video.userId === userId) return;
    await this.interactions.recordView(userId, videoId);
  }

  // Pour le module feed : historique de visionnage de `userId`, du plus récent au plus ancien, après `after`.
  listViewedVideos(userId: string, after: ViewPosition | null, limit: number): Promise<ViewPosition[]> {
    return this.interactions.listViews(userId, after, limit);
  }

  // Retire une vidéo de son historique (idempotent). `views_count` ne baisse pas.
  removeFromHistory(userId: string, videoId: string): Promise<void> {
    return this.interactions.removeView(userId, videoId);
  }

  // Efface tout son historique. `views_count` ne baisse pas.
  clearHistory(userId: string): Promise<void> {
    return this.interactions.clearViews(userId);
  }

  // Partage (lien envoyé depuis la feuille de partage de l'app) : compteur seul, sans table (ADR-006).
  async share(videoId: string): Promise<number> {
    const sharesCount = await this.videos.recordShare(videoId);
    if (sharesCount === null) throw new VideoNotAvailableError(videoId);
    return sharesCount;
  }

  // Suivre (`active`) ou ne plus suivre un compte. Idempotent. Renvoie le nombre d'abonnés du compte.
  async setFollow(followerId: string, username: string, active: boolean): Promise<InteractionState> {
    const target = await this.userByUsername(username);
    if (target.id === followerId) throw new CannotFollowYourselfError();
    if (active) await this.assertNotBlocked(followerId, target.id);
    if (active) await this.interactions.follow(followerId, target.id);
    else await this.interactions.unfollow(followerId, target.id);

    const activity = { type: 'follow', actorId: followerId, recipientId: target.id } as const;
    if (active) await this.notifications.notify(activity);
    else await this.notifications.retract(activity);
    const updated = await this.users.getById(target.id);
    return { active, count: updated.followersCount };
  }

  // Abonnés ou abonnements de @username, du follow le plus récent au plus ancien. Listes publiques
  // (lisibles en mode invité) ; les comptes bloqués n'en sont pas retirés. `viewerId` : compte connecté,
  // dont on donne la relation avec chaque compte listé (boutons « Suivre », « Suivre en retour »).
  async listFollows(
    direction: FollowDirection,
    username: string,
    viewerId: string | undefined,
    cursor: string | null,
    limit: number,
  ): Promise<FollowPage> {
    const target = await this.userByUsername(username);
    const after = cursor ? decodeFollowCursor(cursor) : null;
    const rows = await this.interactions.listFollows(direction, target.id, after, limit + 1);
    const page = rows.slice(0, limit);
    const ids = page.map((row) => row.userId);
    const [users, relations] = await Promise.all([
      this.users.getByIds(ids),
      viewerId ? this.interactions.findFollowRelations(viewerId, ids) : null,
    ]);
    const byId = new Map(users.map((u) => [u.id, u]));
    return {
      // Un compte supprimé entre-temps est sauté (la cascade supprime de toute façon ses follows).
      items: page.flatMap(({ userId, followedAt }) => {
        const user = byId.get(userId);
        if (!user) return [];
        const viewer = relations && { following: relations.following.has(userId), followedBy: relations.followedBy.has(userId) };
        return [{ user, followedAt, ...(viewer ? { viewer } : {}) }];
      }),
      nextCursor: rows.length > limit ? encodeFollowCursor(page.at(-1)!) : null,
    };
  }

  async addComment(userId: string, videoId: string, content: string): Promise<CommentWithAuthor> {
    const text = content.trim();
    if (!text) throw new EmptyCommentError();
    const video = await this.publishedVideo(videoId);
    await this.assertNotBlocked(userId, video.userId);
    const comment = await this.interactions.createComment({ videoId, userId, content: text });
    await this.notifications.notify({
      type: 'comment',
      actorId: userId,
      recipientId: video.userId,
      videoId,
      commentId: comment.id,
      commentText: comment.content,
    });
    return { comment, author: await this.users.getById(userId) };
  }

  // Seul l'auteur supprime son commentaire (la modération par l'auteur de la vidéo viendra plus tard).
  // Sa notification disparaît avec lui (cascade de la base).
  async deleteComment(userId: string, commentId: string): Promise<void> {
    const comment = await this.interactions.findComment(commentId);
    if (!comment) throw new CommentNotFoundError(commentId);
    if (comment.userId !== userId) throw new NotCommentAuthorError();
    await this.interactions.deleteComment(commentId);
  }

  // Commentaires d'une vidéo publiée, du plus récent au plus ancien. Le curseur est l'identifiant
  // du dernier commentaire reçu (UUID v7, ordonné dans le temps) : stable même si d'autres arrivent.
  async listComments(videoId: string, cursor: string | null, limit: number): Promise<CommentPage> {
    await this.publishedVideo(videoId);
    const rows = await this.interactions.listComments(videoId, cursor, limit + 1);
    const page = rows.slice(0, limit);
    const authors = new Map((await this.users.getByIds(page.map((c) => c.userId))).map((u) => [u.id, u]));
    return {
      items: page.flatMap((comment) => {
        const author = authors.get(comment.userId);
        return author ? [{ comment, author }] : [];
      }),
      nextCursor: rows.length > limit ? page.at(-1)!.id : null,
    };
  }

  // Relation entre le compte connecté et @username (boutons de l'écran de profil). Avec soi-même : tout est faux.
  // Qu'un compte ait bloqué le compte connecté n'est pas révélé (comme dans la messagerie).
  async getRelationship(viewerId: string, username: string): Promise<Relationship> {
    const target = await this.userByUsername(username);
    const [follows, blocks] = await Promise.all([
      this.interactions.findFollowRelations(viewerId, [target.id]),
      this.interactions.findBlocks(viewerId, [target.id]),
    ]);
    return {
      following: follows.following.has(target.id),
      followedBy: follows.followedBy.has(target.id),
      blockedByMe: blocks.blockedByMe.has(target.id),
    };
  }

  // Pour le module feed : vidéos likées, mises en favori ou republiées par `userId`, de la plus récente action
  // à la plus ancienne, strictement après `after`. Vidéos non filtrées : le feed ne garde que les publiées.
  listReactedVideos(kind: VideoReaction, userId: string, after: ReactionPosition | null, limit: number): Promise<ReactionPosition[]> {
    return this.interactions.listReactions(kind, userId, after, limit);
  }

  // Historique des commentaires de `userId` (centre d'activités, ADR-006 : lu dans la table comments, sans
  // nouvelle entité), du plus récent au plus ancien. Privé. Un commentaire dont la vidéo ou son auteur a disparu
  // entre-temps est sauté (la cascade le supprime de toute façon).
  async listCommentHistory(userId: string, cursor: string | null, limit: number): Promise<CommentHistoryPage> {
    const rows = await this.interactions.listUserComments(userId, cursor, limit + 1);
    const page = rows.slice(0, limit);
    const videos = new Map((await this.videos.getPublishedVideos([...new Set(page.map((c) => c.videoId))])).map((v) => [v.id, v]));
    const authors = new Map((await this.users.getByIds([...videos.values()].map((v) => v.userId))).map((u) => [u.id, u]));
    return {
      items: page.flatMap((comment) => {
        const video = videos.get(comment.videoId);
        const videoAuthor = video && authors.get(video.userId);
        return video && videoAuthor ? [{ comment, video, videoAuthor }] : [];
      }),
      nextCursor: rows.length > limit ? page.at(-1)!.id : null,
    };
  }

  // Pour le module feed : ce que `userId` a fait sur ces vidéos et ces auteurs.
  getViewerInteractions(userId: string, videos: { id: string; userId: string }[]): Promise<ViewerInteractions> {
    return this.interactions.findViewerInteractions(
      userId,
      videos.map((v) => v.id),
      [...new Set(videos.map((v) => v.userId))],
    );
  }

  // Bloque (`active`) ou débloque @username. Idempotent. Bloquer supprime les follows dans les deux sens
  // et les notifications échangées ; débloquer ne les rétablit pas.
  async setBlock(blockerId: string, username: string, active: boolean): Promise<void> {
    const target = await this.userByUsername(username);
    if (target.id === blockerId) throw new CannotBlockYourselfError();
    if (!active) return this.interactions.unblock(blockerId, target.id);
    await this.interactions.block(blockerId, target.id);
    await this.notifications.removeBetween(blockerId, target.id);
  }

  // Comptes bloqués par `userId`, du plus récent au plus ancien (réglages de l'app, pour débloquer).
  async listBlockedUsers(userId: string): Promise<User[]> {
    const ids = await this.interactions.listBlocked(userId);
    const users = new Map((await this.users.getByIds(ids)).map((u) => [u.id, u]));
    return ids.flatMap((id) => users.get(id) ?? []);
  }

  // Pour le module messaging : blocages entre `userId` et ces comptes, dans les deux sens.
  getBlocks(userId: string, userIds: string[]): Promise<BlockRelations> {
    return this.interactions.findBlocks(userId, [...new Set(userIds)]);
  }

  // Pour le module messaging : parmi `userIds`, les abonnés mutuels de `userId` (seuls autorisés à s'écrire).
  getMutualFollowers(userId: string, userIds: string[]): Promise<Set<string>> {
    return this.interactions.findMutualFollows(userId, [...new Set(userIds)]);
  }

  // Sur ses propres vidéos, pas de blocage possible (on ne se bloque pas soi-même).
  private async assertNotBlocked(userId: string, otherId: string): Promise<void> {
    if (userId !== otherId && (await this.interactions.isBlockedBetween(userId, otherId))) throw new BlockedError();
  }

  private async publishedVideo(videoId: string): Promise<PublishedVideo> {
    const [video] = await this.videos.getPublishedVideos([videoId]);
    if (!video) throw new VideoNotAvailableError(videoId);
    return video;
  }

  private async userByUsername(username: string): Promise<User> {
    try {
      return await this.users.getByUsername(username);
    } catch (error) {
      if (error instanceof UserNotFoundError) throw new TargetUserNotFoundError(username);
      throw error;
    }
  }
}
