import { randomInt, randomUUID } from 'node:crypto';
import type { InteractionsService } from '../../interactions/application/interactions.service';
import type { VideoReaction } from '../../interactions/domain/interaction';
import type { StoriesService } from '../../stories/application/stories.service';
import type { User } from '../../users/domain/user';
import type { UsersService } from '../../users/application/users.service';
import type { PublishedVideo } from '../../videos/domain/video';
import type { VideosService } from '../../videos/application/videos.service';
import { decodeCursor, encodeCursor, type FeedPosition } from '../domain/feed-cursor';
import { FeedItemNotFoundError } from '../domain/feed.errors';
import { decodeListCursor, encodeListCursor } from '../domain/list-cursor';
import { CATALOG_LIMIT, PAGE_FILL_ROUNDS, SNAPSHOT_REFRESH_SECONDS, SNAPSHOT_TTL_SECONDS } from '../domain/feed-rules';
import type { FeedSnapshot, FeedSnapshotStore } from '../domain/feed-snapshot.store';
import { seededShuffle } from '../domain/seeded-shuffle';

export interface FeedViewerState {
  liked: boolean;
  favorited: boolean;
  reposted: boolean;
  followingAuthor: boolean;
}

export interface FeedItem {
  video: PublishedVideo;
  author: User;
  // Null en mode invité.
  viewer: FeedViewerState | null;
  // Anneau autour de l'avatar (ADR-051) : null si l'auteur n'a pas de story visible.
  authorStory: { hasUnseen: boolean } | null;
  // Historique de visionnage seulement (ADR-057) : dernière vue de la vidéo par le compte.
  viewedAt?: Date;
}

export interface FeedPage {
  items: FeedItem[];
  nextCursor: string | null;
}

// Feed principal (ADR-016) : toutes les vidéos publiées, dans un ordre aléatoire propre à chaque session.
// Feed des abonnements (ADR-048) : vidéos des comptes suivis, de la plus récente à la plus ancienne.
// Page d'un hashtag (ADR-049) : ses vidéos, de la plus récemment publiée à la plus ancienne.
// Le module sert aussi les grilles du profil (vidéos, republications, favoris d'un compte), avec le même
// élément que le feed : l'app les ouvre dans le même lecteur.
// - Nouvelle session (sans curseur) : photo courante du catalogue (cache Redis, ADR-014) + graine aléatoire.
// - Pages suivantes : même photo, même graine, donc même ordre → ni doublon ni vidéo manquée.
// Vidéos, auteurs et état du lecteur passent par les services exportés de `videos`, `users`
// et `interactions` (ADR-003).
// Blocage : pour un compte connecté, les vidéos des comptes bloqués dans un sens ou dans l'autre sont retirées
// de toutes les listes (feed, grilles, historique), et une telle vidéo seule est introuvable. Même règle pour les
// grilles d'un tel compte : vides. Rien n'est filtré en mode invité.
export class FeedService {
  constructor(
    private readonly snapshots: FeedSnapshotStore,
    private readonly videos: VideosService,
    private readonly users: UsersService,
    private readonly interactions: InteractionsService,
    private readonly stories: StoriesService,
  ) {}

  // Lève InvalidFeedCursorError si le curseur n'a pas été produit par l'API.
  // `viewerId` : utilisateur connecté, pour l'état des boutons (liké, suivi…) ; null en mode invité.
  async getPage(cursor: string | undefined, limit: number, viewerId: string | null = null): Promise<FeedPage> {
    const requested = cursor ? decodeCursor(cursor) : null;
    const resumed = requested ? await this.snapshots.get(requested.snapshotId) : null;

    // Sans curseur, ou photo expirée (session de plus de 2 h) : nouvelle session, nouvel ordre.
    let snapshot: FeedSnapshot;
    let position: FeedPosition;
    if (requested && resumed) {
      snapshot = resumed;
      position = requested;
    } else {
      snapshot = await this.currentSnapshot();
      position = { snapshotId: snapshot.id, seed: randomInt(2 ** 31), offset: 0 };
    }

    const order = seededShuffle(snapshot.videoIds, position.seed);
    const hidden = await this.hiddenAccounts(viewerId);
    // Des vidéos sautées (compte bloqué, vidéo supprimée) : la page est complétée avec les suivantes de l'ordre.
    const items: FeedItem[] = [];
    let offset = position.offset;
    for (let round = 0; round < PAGE_FILL_ROUNDS && items.length < limit && offset < order.length; round++) {
      const ids = order.slice(offset, offset + limit - items.length);
      offset += ids.length;
      items.push(...(await this.loadItems(ids, viewerId, hidden)));
    }

    return {
      items,
      nextCursor: offset < order.length ? encodeCursor({ ...position, offset }) : null,
    };
  }

  // Une vidéo publiée seule, sous la forme d'un élément du feed : pour l'ouvrir dans le lecteur depuis une
  // notification, l'historique des commentaires, un message partagé ou un lien. Publique (mode invité compris).
  async getItem(videoId: string, viewerId: string | null): Promise<FeedItem> {
    const [item] = await this.loadItems([videoId], viewerId, await this.hiddenAccounts(viewerId));
    if (!item) throw new FeedItemNotFoundError(videoId);
    return item;
  }

  // Vidéos publiées de @username, de la plus récente à la plus ancienne. Publique (mode invité compris).
  // Lève UserNotFoundError pour un pseudo inconnu, InvalidFeedCursorError pour un curseur invalide.
  async listAuthorVideos(username: string, cursor: string | undefined, limit: number, viewerId: string | null): Promise<FeedPage> {
    const [author, hidden] = await Promise.all([this.users.getByUsername(username), this.hiddenAccounts(viewerId)]);
    const after = cursor ? decodeListCursor(cursor) : null;
    if (hidden.has(author.id)) return { items: [], nextCursor: null };
    const rows = await this.videos.listPublishedByAuthor(author.id, after && { createdAt: after.at, id: after.videoId }, limit + 1);
    const page = rows.slice(0, limit);
    const last = page.at(-1);
    return {
      items: await this.toItems(page, viewerId, hidden),
      nextCursor: rows.length > limit && last ? encodeListCursor({ at: last.createdAt, videoId: last.id }) : null,
    };
  }

  // Feed des abonnements (ADR-048) : vidéos publiées des comptes que suit `viewerId`, de la plus récente à la plus
  // ancienne. Pas d'ordre aléatoire ni de session : une pagination par clé, comme les grilles, et une vraie fin
  // (`nextCursor` nul). Ni ses propres vidéos ni les republications. Les comptes masqués (suspendus) sont retirés
  // avant la lecture : pas de page raccourcie par eux. Une vidéo publiée pendant le parcours apparaît au
  // prochain rechargement (sans curseur).
  async listFollowing(viewerId: string, cursor: string | undefined, limit: number): Promise<FeedPage> {
    return this.listByAuthors(await this.interactions.listVisibleFollowingIds(viewerId), viewerId, cursor, limit);
  }

  // Feed des amis (ADR-054) : comme le feed des abonnements, limité aux amis (abonnés mutuels) de `viewerId`.
  async listFriends(viewerId: string, cursor: string | undefined, limit: number): Promise<FeedPage> {
    return this.listByAuthors(await this.interactions.listVisibleFriendIds(viewerId), viewerId, cursor, limit);
  }

  // Vidéos publiées de `authors`, de la plus récente à la plus ancienne, pagination par clé (feeds des abonnements et
  // des amis). Lève InvalidFeedCursorError pour un curseur invalide.
  private async listByAuthors(authors: string[], viewerId: string, cursor: string | undefined, limit: number): Promise<FeedPage> {
    const after = cursor ? decodeListCursor(cursor) : null;
    const rows = await this.videos.listPublishedByAuthors(authors, after && { createdAt: after.at, id: after.videoId }, limit + 1);
    const page = rows.slice(0, limit);
    const last = page.at(-1);
    return {
      items: await this.toItems(page, viewerId, new Set()),
      nextCursor: rows.length > limit && last ? encodeListCursor({ at: last.createdAt, videoId: last.id }) : null,
    };
  }

  // Page d'un hashtag (ADR-049) : ses vidéos publiées, de la plus récente à la plus ancienne (date de publication).
  // Publique. Vidéos des comptes masqués retirées (page plus courte, curseur inchangé). Lève InvalidHashtagError
  // (module videos) pour un nom invalide, InvalidFeedCursorError pour un curseur invalide.
  async listHashtagVideos(name: string, cursor: string | undefined, limit: number, viewerId: string | null): Promise<FeedPage> {
    const after = cursor ? decodeListCursor(cursor) : null;
    const [rows, hidden] = await Promise.all([
      this.videos.listHashtagVideos(name, after && { videoId: after.videoId, taggedAt: after.at }, limit + 1),
      this.hiddenAccounts(viewerId),
    ]);
    const page = rows.slice(0, limit);
    const last = page.at(-1);
    return {
      items: await this.loadItems(
        page.map((row) => row.videoId),
        viewerId,
        hidden,
      ),
      nextCursor: rows.length > limit && last ? encodeListCursor({ at: last.taggedAt, videoId: last.videoId }) : null,
    };
  }

  // Vidéos republiées par @username, de la republication la plus récente à la plus ancienne. Publique.
  async listReposts(username: string, cursor: string | undefined, limit: number, viewerId: string | null): Promise<FeedPage> {
    const [user, hidden] = await Promise.all([this.users.getByUsername(username), this.hiddenAccounts(viewerId)]);
    if (hidden.has(user.id)) {
      if (cursor) decodeListCursor(cursor); // un curseur invalide reste une erreur (400)
      return { items: [], nextCursor: null };
    }
    return this.listReacted('repost', user.id, cursor, limit, viewerId, hidden);
  }

  // Favoris du compte connecté, du plus récent au plus ancien. Privés : seul leur titulaire les voit.
  listFavorites(userId: string, cursor: string | undefined, limit: number): Promise<FeedPage> {
    return this.listReacted('favorite', userId, cursor, limit, userId);
  }

  // Vidéos likées par le compte connecté, du like le plus récent au plus ancien. Privées, comme les favoris.
  listLikes(userId: string, cursor: string | undefined, limit: number): Promise<FeedPage> {
    return this.listReacted('like', userId, cursor, limit, userId);
  }

  // Historique de visionnage du compte connecté, du plus récent au plus ancien. Privé. Une vidéo revue remonte
  // en tête : pendant qu'on parcourt l'historique, elle peut manquer dans les pages suivantes.
  async listHistory(userId: string, cursor: string | undefined, limit: number): Promise<FeedPage> {
    const after = cursor ? decodeListCursor(cursor) : null;
    const [rows, hidden] = await Promise.all([
      this.interactions.listViewedVideos(userId, after && { videoId: after.videoId, viewedAt: after.at }, limit + 1),
      this.hiddenAccounts(userId),
    ]);
    const page = rows.slice(0, limit);
    const last = page.at(-1);
    const viewedAt = new Map(page.map((row) => [row.videoId, row.viewedAt]));
    const items = await this.loadItems(
      page.map((row) => row.videoId),
      userId,
      hidden,
    );
    return {
      items: items.map((item) => ({ ...item, viewedAt: viewedAt.get(item.video.id) })),
      nextCursor: rows.length > limit && last ? encodeListCursor({ at: last.viewedAt, videoId: last.videoId }) : null,
    };
  }

  // La pagination suit les lignes de favoris ou de republications, pas les vidéos affichées : une vidéo
  // supprimée entre-temps est sautée (page plus courte), sans décaler les pages suivantes.
  private async listReacted(
    kind: VideoReaction,
    userId: string,
    cursor: string | undefined,
    limit: number,
    viewerId: string | null,
    knownHidden?: Set<string>,
  ): Promise<FeedPage> {
    const after = cursor ? decodeListCursor(cursor) : null;
    const [rows, hidden] = await Promise.all([
      this.interactions.listReactedVideos(kind, userId, after && { videoId: after.videoId, reactedAt: after.at }, limit + 1),
      knownHidden ?? this.hiddenAccounts(viewerId),
    ]);
    const page = rows.slice(0, limit);
    const last = page.at(-1);
    return {
      items: await this.loadItems(
        page.map((row) => row.videoId),
        viewerId,
        hidden,
      ),
      nextCursor: rows.length > limit && last ? encodeListCursor({ at: last.reactedAt, videoId: last.videoId }) : null,
    };
  }

  private async currentSnapshot(): Promise<FeedSnapshot> {
    const current = await this.snapshots.getCurrent();
    if (current) return current;
    const snapshot = { id: randomUUID(), videoIds: await this.videos.listPublishedVideoIds(CATALOG_LIMIT) };
    await this.snapshots.save(snapshot, SNAPSHOT_REFRESH_SECONDS, SNAPSHOT_TTL_SECONDS);
    return snapshot;
  }

  // Comptes dont les vidéos sont masquées : suspendus pour tous (ADR-037), et bloqués dans un sens ou dans l'autre
  // pour un compte connecté (ADR-029).
  private hiddenAccounts(viewerId: string | null): Promise<Set<string>> {
    return this.interactions.getHiddenAccountIds(viewerId);
  }

  // Remet les vidéos dans l'ordre de la page. Une vidéo supprimée (ou son auteur) depuis la photo est
  // simplement absente : la page peut être plus courte, la pagination continue.
  private async loadItems(ids: string[], viewerId: string | null, hidden: Set<string>): Promise<FeedItem[]> {
    const videos = new Map((await this.videos.getPublishedVideos(ids)).map((v) => [v.id, v]));
    return this.toItems(
      ids.flatMap((id) => videos.get(id) ?? []),
      viewerId,
      hidden,
    );
  }

  // Ajoute auteur, état du lecteur et anneau de story de l'auteur, dans l'ordre donné. Une vidéo dont l'auteur a disparu,
  // ou d'un compte masqué (`hidden`), est sautée.
  private async toItems(all: PublishedVideo[], viewerId: string | null, hidden: Set<string>): Promise<FeedItem[]> {
    const videos = all.filter((video) => !hidden.has(video.userId));
    const authorIds = videos.map((v) => v.userId);
    const [authorList, seen, rings] = await Promise.all([
      this.users.getByIds(authorIds),
      viewerId ? this.interactions.getViewerInteractions(viewerId, videos) : null,
      this.stories.getStoryRings(authorIds, viewerId),
    ]);
    const authors = new Map(authorList.map((u) => [u.id, u]));
    return videos.flatMap((video) => {
      const author = authors.get(video.userId);
      if (!author) return [];
      const viewer = seen && {
        liked: seen.likedVideoIds.has(video.id),
        favorited: seen.favoritedVideoIds.has(video.id),
        reposted: seen.repostedVideoIds.has(video.id),
        followingAuthor: seen.followedUserIds.has(author.id),
      };
      return [{ video, author, viewer, authorStory: rings.get(author.id) ?? null }];
    });
  }
}
