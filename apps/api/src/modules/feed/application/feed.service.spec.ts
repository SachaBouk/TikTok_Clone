import { beforeEach, describe, expect, it } from 'vitest';
import { InMemoryProfileCountersPublisher } from '../../interactions/infrastructure/in-memory-profile-counters-publisher';
import { InteractionsService } from '../../interactions/application/interactions.service';
import { InMemoryInteractionRepository } from '../../interactions/infrastructure/in-memory-interaction.repository';
import { NotificationsService } from '../../notifications/application/notifications.service';
import { InMemoryNotificationPublisher } from '../../notifications/infrastructure/in-memory-notification-publisher';
import { InMemoryNotificationRepository } from '../../notifications/infrastructure/in-memory-notification.repository';
import { UsersService } from '../../users/application/users.service';
import type { User } from '../../users/domain/user';
import { UserNotFoundError } from '../../users/domain/user.errors';
import { InMemoryUserRepository } from '../../users/infrastructure/in-memory-user.repository';
import { InMemoryAvatarStorage } from '../../users/infrastructure/in-memory-avatar-storage';
import { InMemoryAccountContentCleanup } from '../../users/infrastructure/in-memory-account-content-cleanup';
import { VideosService } from '../../videos/application/videos.service';
import { TranscodingQueue } from '../../videos/domain/transcoding-queue';
import { InMemoryVideoEventPublisher } from '../../videos/infrastructure/in-memory-video-event-publisher';
import { InMemoryVideoCleanupQueue } from '../../videos/infrastructure/in-memory-video-cleanup-queue';
import { InvalidHashtagError } from '../../videos/domain/video.errors';
import { InMemoryVideoRepository } from '../../videos/infrastructure/in-memory-video.repository';
import { InMemoryVideoStorage } from '../../videos/infrastructure/in-memory-video-storage';
import { encodeCursor, InvalidFeedCursorError } from '../domain/feed-cursor';
import { FeedItemNotFoundError } from '../domain/feed.errors';
import { encodeListCursor } from '../domain/list-cursor';
import { seededShuffle } from '../domain/seeded-shuffle';
import { InMemoryFeedSnapshotStore } from '../infrastructure/in-memory-feed-snapshot.store';
import { FeedService } from './feed.service';
import { InMemoryRateLimiter } from '../../../rate-limit/in-memory-rate-limiter';
import { InMemorySuspendedAccounts } from '../../../suspension/in-memory-suspended-accounts';

// Registre des comptes suspendus (ADR-037), partagé par les services d'un même test.
let suspended = new InMemorySuspendedAccounts();

class NoopTranscodingQueue extends TranscodingQueue {
  async enqueue() {}
  async cancel() {}
}

const user = (id: string): User => ({
  id,
  username: id,
  displayName: id.toUpperCase(),
  avatarUrl: null,
  bio: null,
  followersCount: 0,
  followingCount: 0,
  createdAt: new Date('2026-01-01T00:00:00Z'),
});

describe('FeedService', () => {
  let videoRepository: InMemoryVideoRepository;
  let users: InMemoryUserRepository;
  let snapshots: InMemoryFeedSnapshotStore;
  let interactions: InteractionsService;
  let feed: FeedService;

  // Crée une vidéo publiée (`ready`) directement dans le dépôt en mémoire.
  async function publish(userId = 'alice', status: 'ready' | 'processing' = 'ready') {
    const video = await videoRepository.create({ userId, description: null, rawKey: 'k', uploadId: 'u', rawSize: 1 });
    Object.assign(videoRepository.videos.get(video.id)!, { status, hlsUrl: `https://cdn/${video.id}/master.m3u8`, thumbnailUrl: 't' });
    return video.id;
  }

  // Parcourt toute la session à partir de `cursor` et renvoie les identifiants vus, page par page.
  async function scrollAll(limit: number, cursor?: string) {
    const pages: string[][] = [];
    do {
      const page = await feed.getPage(cursor, limit);
      pages.push(page.items.map((i) => i.video.id));
      cursor = page.nextCursor ?? undefined;
    } while (cursor);
    return pages;
  }

  beforeEach(() => {
    // Dates de création strictement croissantes : ordre des grilles du profil déterministe.
    let tick = 0;
    videoRepository = new InMemoryVideoRepository(() => new Date(Date.UTC(2026, 0, 1) + ++tick * 1000));
    users = new InMemoryUserRepository([user('alice'), user('bob'), user('dave')]);
    snapshots = new InMemoryFeedSnapshotStore();
    const videos = new VideosService(
      videoRepository,
      new InMemoryVideoStorage(),
      new NoopTranscodingQueue(),
      new InMemoryVideoEventPublisher(),
      new InMemoryVideoCleanupQueue(),
      new InMemoryRateLimiter(),
    );
    suspended = new InMemorySuspendedAccounts();
    const usersService = new UsersService(users, new InMemoryAvatarStorage(), new InMemoryAccountContentCleanup(), suspended);
    const notifications = new NotificationsService(
      new InMemoryNotificationRepository(),
      usersService,
      videos,
      new InMemoryNotificationPublisher(),
      suspended,
    );
    interactions = new InteractionsService(
      new InMemoryInteractionRepository(videoRepository, users),
      videos,
      usersService,
      notifications,
      new InMemoryRateLimiter(),
      suspended,
      new InMemoryProfileCountersPublisher(),
    );
    feed = new FeedService(snapshots, videos, usersService, interactions);
  });

  it('parcourt toutes les vidéos publiées, sans doublon ni oubli, page par page', async () => {
    const ids = await Promise.all(Array.from({ length: 25 }, (_, i) => publish(i % 2 ? 'alice' : 'bob')));
    const pages = await scrollAll(10);

    expect(pages.map((p) => p.length)).toEqual([10, 10, 5]);
    expect(pages.flat().sort()).toEqual([...ids].sort());
  });

  it("n'affiche que les vidéos publiées", async () => {
    const ready = await publish();
    await publish('alice', 'processing');
    expect((await scrollAll(10)).flat()).toEqual([ready]);
  });

  it("joint l'auteur de chaque vidéo", async () => {
    await publish('bob');
    const { items } = await feed.getPage(undefined, 10);
    expect(items[0].author).toMatchObject({ id: 'bob', displayName: 'BOB' });
  });

  it("donne l'état des boutons à l'utilisateur connecté, et rien en mode invité", async () => {
    const liked = await publish('bob');
    const other = await publish('alice');
    await interactions.setReaction('alice', liked, 'like', true);
    await interactions.setReaction('alice', liked, 'repost', true);
    await interactions.setFollow('alice', 'bob', true);

    const { items } = await feed.getPage(undefined, 10, 'alice');
    const state = (id: string) => items.find((i) => i.video.id === id)!;
    expect(state(liked).viewer).toEqual({ liked: true, favorited: false, reposted: true, followingAuthor: true });
    expect(state(other).viewer).toEqual({ liked: false, favorited: false, reposted: false, followingAuthor: false });
    expect(state(liked).video.likesCount).toBe(1);

    expect((await feed.getPage(undefined, 10)).items.every((i) => i.viewer === null)).toBe(true);
  });

  it('donne un ordre différent à chaque session, reproductible au sein de la session', async () => {
    await Promise.all(Array.from({ length: 30 }, () => publish()));
    const first = await feed.getPage(undefined, 30);
    const second = await feed.getPage(undefined, 30);
    expect(first.items.map((i) => i.video.id)).not.toEqual(second.items.map((i) => i.video.id));
    // Même photo : les deux sessions partagent le cache.
    expect(snapshots.snapshots.size).toBe(1);

    const session = await feed.getPage(undefined, 5);
    const replayed = await feed.getPage(session.nextCursor!, 5);
    const again = await feed.getPage(session.nextCursor!, 5);
    expect(replayed.items.map((i) => i.video.id)).toEqual(again.items.map((i) => i.video.id));
  });

  it('une vidéo publiée en cours de session n’apparaît pas dans cette session, mais dans la suivante après renouvellement', async () => {
    await Promise.all(Array.from({ length: 4 }, () => publish()));
    const firstPage = await feed.getPage(undefined, 2);
    const late = await publish();

    const rest = await scrollAll(2, firstPage.nextCursor!);
    expect(rest.flat()).not.toContain(late);

    expect((await scrollAll(10)).flat()).not.toContain(late); // photo courante encore valide
    snapshots.expireCurrent();
    expect((await scrollAll(10)).flat()).toContain(late);
  });

  it('saute une vidéo supprimée depuis la photo, sans casser la pagination', async () => {
    await Promise.all(Array.from({ length: 6 }, () => publish()));
    const first = await feed.getPage(undefined, 3);
    const upcoming = seededShuffle(snapshots.snapshots.values().next().value!.videoIds, decodeSeed(first.nextCursor!));
    await videoRepository.delete(upcoming[3]);

    const second = await feed.getPage(first.nextCursor!, 3);
    expect(second.items.map((i) => i.video.id)).toEqual(upcoming.slice(4, 6));
    expect(second.nextCursor).toBeNull();
  });

  it('repart sur une nouvelle session si la photo a expiré', async () => {
    await Promise.all(Array.from({ length: 4 }, () => publish()));
    const first = await feed.getPage(undefined, 2);
    snapshots.expire([...snapshots.snapshots.keys()][0]);

    const page = await feed.getPage(first.nextCursor!, 2);
    expect(page.items).toHaveLength(2);
    expect(snapshots.snapshots.size).toBe(1); // nouvelle photo
  });

  it('refuse un curseur qui n’a pas été produit par l’API', async () => {
    await expect(feed.getPage('pas-un-curseur', 10)).rejects.toBeInstanceOf(InvalidFeedCursorError);
    const forged = Buffer.from(JSON.stringify({ s: 'x', r: 1, o: -5 })).toString('base64url');
    await expect(feed.getPage(forged, 10)).rejects.toBeInstanceOf(InvalidFeedCursorError);
  });

  describe('grilles du profil', () => {
    // Parcourt toute une grille, page par page, et renvoie les identifiants des vidéos.
    async function readAll(list: (cursor: string | undefined) => ReturnType<FeedService['listAuthorVideos']>) {
      const pages: string[][] = [];
      let cursor: string | undefined;
      do {
        const page = await list(cursor);
        pages.push(page.items.map((i) => i.video.id));
        cursor = page.nextCursor ?? undefined;
      } while (cursor);
      return pages;
    }

    it("liste les vidéos publiées d'un compte, de la plus récente à la plus ancienne, page par page", async () => {
      const first = await publish('alice');
      await publish('bob');
      await publish('alice', 'processing');
      const second = await publish('alice');
      const third = await publish('alice');

      const pages = await readAll((cursor) => feed.listAuthorVideos('alice', cursor, 2, null));
      expect(pages).toEqual([[third, second], [first]]);
      await expect(feed.listAuthorVideos('bob', undefined, 1, null)).resolves.toMatchObject({ nextCursor: null });
    });

    it('départage les vidéos publiées à la même date sans en perdre', async () => {
      const ids = await Promise.all(Array.from({ length: 5 }, () => publish('alice')));
      for (const id of ids) videoRepository.videos.get(id)!.createdAt = new Date('2026-06-01T00:00:00Z');
      const pages = await readAll((cursor) => feed.listAuthorVideos('alice', cursor, 1, null));
      expect(pages.flat()).toEqual([...ids].sort().reverse());
    });

    it("porte l'auteur et l'état des boutons pour un compte connecté", async () => {
      const video = await publish('bob');
      await interactions.setReaction('alice', video, 'like', true);
      const { items } = await feed.listAuthorVideos('bob', undefined, 10, 'alice');
      expect(items[0].author).toMatchObject({ id: 'bob' });
      expect(items[0].viewer).toEqual({ liked: true, favorited: false, reposted: false, followingAuthor: false });
      expect((await feed.listAuthorVideos('bob', undefined, 10, null)).items[0].viewer).toBeNull();
    });

    it('liste les republications, de la plus récente à la plus ancienne', async () => {
      const [a, b, c] = [await publish('bob'), await publish('bob'), await publish('alice')];
      for (const id of [b, a, c]) await interactions.setReaction('alice', id, 'repost', true);
      await interactions.setReaction('bob', a, 'repost', true);

      const pages = await readAll((cursor) => feed.listReposts('alice', cursor, 2, 'bob'));
      expect(pages).toEqual([[c, a], [b]]);
      const { items } = await feed.listReposts('alice', undefined, 10, 'bob');
      // Chaque vidéo garde son propre auteur ; `viewer` est celui du compte connecté (bob).
      expect(items.map((i) => i.author.id)).toEqual(['alice', 'bob', 'bob']);
      expect(items[1].viewer).toMatchObject({ reposted: true });
    });

    it('saute une vidéo supprimée depuis, sans décaler la pagination', async () => {
      const ids = [await publish('bob'), await publish('bob'), await publish('bob')];
      for (const id of ids) await interactions.setReaction('alice', id, 'repost', true);
      await videoRepository.delete(ids[1]);
      const first = await feed.listReposts('alice', undefined, 2, null);
      expect(first.items.map((i) => i.video.id)).toEqual([ids[2]]);
      const second = await feed.listReposts('alice', first.nextCursor!, 2, null);
      expect(second).toMatchObject({ nextCursor: null });
      expect(second.items.map((i) => i.video.id)).toEqual([ids[0]]);
    });

    it('liste les favoris du compte connecté seulement', async () => {
      const [a, b] = [await publish('bob'), await publish('bob')];
      await interactions.setReaction('alice', a, 'favorite', true);
      await interactions.setReaction('alice', b, 'favorite', true);
      await interactions.setReaction('bob', a, 'favorite', true);

      const { items, nextCursor } = await feed.listFavorites('alice', undefined, 10);
      expect(items.map((i) => i.video.id)).toEqual([b, a]);
      expect(items.every((i) => i.viewer?.favorited)).toBe(true);
      expect(nextCursor).toBeNull();
      await expect(feed.listFavorites('bob', undefined, 10).then((p) => p.items.map((i) => i.video.id))).resolves.toEqual([a]);
    });

    it('liste les vidéos likées du compte connecté seulement, likes retirés exclus', async () => {
      const [a, b, c] = [await publish('bob'), await publish('bob'), await publish('alice')];
      for (const id of [a, c, b]) await interactions.setReaction('alice', id, 'like', true);
      await interactions.setReaction('bob', a, 'like', true);
      await interactions.setReaction('alice', c, 'like', false);

      const pages = await readAll((cursor) => feed.listLikes('alice', cursor, 1));
      expect(pages.flat()).toEqual([b, a]);
      const { items } = await feed.listLikes('alice', undefined, 10);
      expect(items.every((i) => i.viewer?.liked)).toBe(true);
      await expect(feed.listLikes('bob', undefined, 10).then((p) => p.items.map((i) => i.video.id))).resolves.toEqual([a]);
    });

    it("liste l'historique du compte connecté, une vidéo revue remontant en tête", async () => {
      const [a, b, c] = [await publish('bob'), await publish('bob'), await publish('bob')];
      for (const id of [a, b, c]) await interactions.recordView('alice', id);
      await interactions.recordView('alice', a);
      await interactions.recordView('carol', b);

      const pages = await readAll((cursor) => feed.listHistory('alice', cursor, 2));
      expect(pages).toEqual([[a, c], [b]]);
      const { items } = await feed.listHistory('alice', undefined, 10);
      expect(items[0].video.viewsCount).toBe(1);
      expect(items.every((i) => i.viewer !== null)).toBe(true);

      // Vidéo supprimée depuis : sautée.
      await videoRepository.delete(c);
      await expect(feed.listHistory('alice', undefined, 10).then((p) => p.items.map((i) => i.video.id))).resolves.toEqual([a, b]);
      await expect(feed.listHistory('bob', undefined, 10)).resolves.toEqual({ items: [], nextCursor: null });
    });

    it('refuse un pseudo inconnu et un curseur invalide', async () => {
      await expect(feed.listAuthorVideos('carol', undefined, 10, null)).rejects.toBeInstanceOf(UserNotFoundError);
      await expect(feed.listReposts('carol', undefined, 10, null)).rejects.toBeInstanceOf(UserNotFoundError);
      for (const cursor of ['???', Buffer.from('{"t":1,"v":"x"}').toString('base64url'), encodeCursor({ snapshotId: 's', seed: 1, offset: 0 })]) {
        await expect(feed.listAuthorVideos('alice', cursor, 10, null)).rejects.toBeInstanceOf(InvalidFeedCursorError);
        await expect(feed.listFavorites('alice', cursor, 10)).rejects.toBeInstanceOf(InvalidFeedCursorError);
      }
    });

    it('le curseur encode la date et la vidéo', () => {
      const videoId = '0192f3a0-0000-7000-8000-000000000001';
      expect(encodeListCursor({ at: new Date(1000), videoId })).toBe(Buffer.from(`{"t":1000,"v":"${videoId}"}`).toString('base64url'));
    });
  });

  describe('vidéo seule', () => {
    it("donne l'élément du feed d'une vidéo publiée, avec l'état des boutons pour un compte connecté", async () => {
      const video = await publish('bob');
      await interactions.setReaction('alice', video, 'like', true);
      await interactions.setFollow('alice', 'bob', true);

      const item = await feed.getItem(video, 'alice');
      expect(item.video).toMatchObject({ id: video, likesCount: 1 });
      expect(item.author).toMatchObject({ id: 'bob' });
      expect(item.viewer).toEqual({ liked: true, favorited: false, reposted: false, followingAuthor: true });
      await expect(feed.getItem(video, null)).resolves.toMatchObject({ viewer: null });
    });

    it('refuse une vidéo non publiée, supprimée ou inconnue', async () => {
      const processing = await publish('bob', 'processing');
      const deleted = await publish('bob');
      await videoRepository.delete(deleted);
      for (const id of [processing, deleted, 'inconnue']) {
        await expect(feed.getItem(id, 'bob')).rejects.toBeInstanceOf(FeedItemNotFoundError);
      }
    });
  });

  describe('feed des abonnements (ADR-048)', () => {
    // Parcourt tout le feed des abonnements de `viewer`, page par page.
    async function readFollowing(viewer: string, limit: number) {
      const pages: string[][] = [];
      let cursor: string | undefined;
      do {
        const page = await feed.listFollowing(viewer, cursor, limit);
        pages.push(page.items.map((i) => i.video.id));
        cursor = page.nextCursor ?? undefined;
      } while (cursor);
      return pages;
    }

    it('donne les vidéos publiées des comptes suivis, de la plus récente à la plus ancienne, jusqu’à une vraie fin', async () => {
      const bobs = [await publish('bob'), await publish('bob')];
      const daves = [await publish('dave'), await publish('dave'), await publish('dave')];
      await publish('dave', 'processing');
      await publish('alice'); // ses propres vidéos n'y sont pas
      await interactions.setFollow('alice', 'bob', true);
      await interactions.setFollow('alice', 'dave', true);

      const pages = await readFollowing('alice', 2);
      expect(pages).toEqual([[daves[2], daves[1]], [daves[0], bobs[1]], [bobs[0]]]);
    });

    it('ne reprend pas les republications des comptes suivis', async () => {
      const daves = await publish('dave');
      await interactions.setFollow('alice', 'bob', true);
      await interactions.setReaction('bob', daves, 'repost', true);
      expect(await feed.listFollowing('alice', undefined, 10)).toEqual({ items: [], nextCursor: null });
    });

    it('est vide sans abonnement', async () => {
      await publish('bob');
      expect(await feed.listFollowing('alice', undefined, 10)).toEqual({ items: [], nextCursor: null });
    });

    it("donne l'état des boutons, auteur suivi compris", async () => {
      const video = await publish('bob');
      await interactions.setFollow('alice', 'bob', true);
      await interactions.setReaction('alice', video, 'like', true);
      const { items } = await feed.listFollowing('alice', undefined, 10);
      expect(items[0]).toMatchObject({ author: { id: 'bob' }, viewer: { liked: true, followingAuthor: true } });
    });

    it('suit les abonnements : un compte quitté ou bloqué en disparaît', async () => {
      await publish('bob');
      await publish('dave');
      await interactions.setFollow('alice', 'bob', true);
      await interactions.setFollow('alice', 'dave', true);
      await interactions.setFollow('alice', 'bob', false);
      await interactions.setBlock('dave', 'alice', true); // le blocage retire le follow, dans les deux sens
      expect((await readFollowing('alice', 10)).flat()).toEqual([]);
    });

    it('retire les vidéos d’un compte suivi suspendu, jusqu’à la levée', async () => {
      const bobs = await publish('bob');
      const daves = await publish('dave');
      await interactions.setFollow('alice', 'bob', true);
      await interactions.setFollow('alice', 'dave', true);
      await suspended.add('bob');
      expect((await readFollowing('alice', 1)).flat()).toEqual([daves]);
      await suspended.remove('bob');
      expect((await readFollowing('alice', 1)).flat()).toEqual([daves, bobs]);
    });

    it('continue sans décalage après une vidéo supprimée, et sans la nouvelle vidéo publiée entre-temps', async () => {
      const videos = [await publish('bob'), await publish('bob'), await publish('bob'), await publish('bob')];
      await interactions.setFollow('alice', 'bob', true);
      const first = await feed.listFollowing('alice', undefined, 2);
      expect(first.items.map((i) => i.video.id)).toEqual([videos[3], videos[2]]);
      await videoRepository.delete(videos[1]);
      const late = await publish('bob');

      const second = await feed.listFollowing('alice', first.nextCursor!, 2);
      expect(second).toMatchObject({ items: [{ video: { id: videos[0] } }], nextCursor: null });
      expect((await feed.listFollowing('alice', undefined, 10)).items[0].video.id).toBe(late);
    });

    it('refuse un curseur qui n’a pas été produit par l’API', async () => {
      await expect(feed.listFollowing('alice', 'pas-un-curseur', 10)).rejects.toBeInstanceOf(InvalidFeedCursorError);
    });
  });

  describe('page d’un hashtag (ADR-049)', () => {
    // Vidéo publiée avec ses hashtags, comme après `finishTranscoding`.
    let published = 0;
    async function publishTagged(userId: string, ...names: string[]) {
      const id = await publish(userId);
      videoRepository.videos.get(id)!.hashtags = { names, taggedAt: new Date(Date.UTC(2026, 1, 1) + ++published * 1000) };
      return id;
    }

    it('donne les vidéos du hashtag, de la plus récemment publiée à la plus ancienne, par pages, avec l’état des boutons', async () => {
      const ids = [
        await publishTagged('bob', 'chat'),
        await publishTagged('dave', 'chien'),
        await publishTagged('dave', 'chat', 'chien'),
        await publishTagged('bob', 'chat'),
      ];
      await interactions.setReaction('alice', ids[3], 'like', true);
      const first = await feed.listHashtagVideos('#Chat', undefined, 2, 'alice');
      expect(first.items.map((i) => i.video.id)).toEqual([ids[3], ids[2]]);
      expect(first.items[0].viewer).toMatchObject({ liked: true });
      const second = await feed.listHashtagVideos('chat', first.nextCursor!, 2, null);
      expect(second).toMatchObject({ items: [{ video: { id: ids[0] }, viewer: null }], nextCursor: null });
    });

    it('retire les vidéos des comptes suspendus et bloqués ; refuse un nom ou un curseur invalide', async () => {
      await publishTagged('bob', 'chat');
      const daves = await publishTagged('dave', 'chat');
      await suspended.add('bob');
      expect((await feed.listHashtagVideos('chat', undefined, 10, null)).items.map((i) => i.video.id)).toEqual([daves]);
      await interactions.setBlock('dave', 'alice', true);
      expect((await feed.listHashtagVideos('chat', undefined, 10, 'alice')).items).toEqual([]);
      await expect(feed.listHashtagVideos('pas valide', undefined, 10, null)).rejects.toBeInstanceOf(InvalidHashtagError);
      await expect(feed.listHashtagVideos('chat', 'pas-un-curseur', 10, null)).rejects.toBeInstanceOf(InvalidFeedCursorError);
    });
  });

  describe('suspension (ADR-037)', () => {
    it('retire du feed, de la vidéo seule et des grilles les vidéos d’un compte suspendu, pour tous', async () => {
      const bobs = await Promise.all(Array.from({ length: 2 }, () => publish('bob')));
      const others = await Promise.all(Array.from({ length: 2 }, () => publish('dave')));
      await suspended.add('bob');

      expect((await scrollAll(3)).flat().sort()).toEqual([...others].sort());
      const page = await feed.getPage(undefined, 10, 'alice');
      expect(page.items.map((i) => i.video.id).sort()).toEqual([...others].sort());
      await expect(feed.getItem(bobs[0], null)).rejects.toBeInstanceOf(FeedItemNotFoundError);
      await expect(feed.listAuthorVideos('bob', undefined, 10, null)).resolves.toMatchObject({ items: [] });

      await suspended.remove('bob');
      await expect(feed.getItem(bobs[0], null)).resolves.toMatchObject({ video: { id: bobs[0] } });
    });
  });

  describe('blocage', () => {
    const ids = (page: { items: { video: { id: string } }[] }) => page.items.map((i) => i.video.id);

    it("retire du feed les vidéos d'un compte bloqué, dans les deux sens, et complète la page avec les suivantes", async () => {
      const bobs = await Promise.all(Array.from({ length: 4 }, () => publish('bob')));
      const others = await Promise.all(Array.from({ length: 4 }, () => publish('dave')));
      await interactions.setBlock('alice', 'bob', true);

      for (const viewer of ['alice', 'bob']) {
        const seen = await (async () => {
          const all: string[] = [];
          let cursor: string | undefined;
          do {
            const page = await feed.getPage(cursor, 3, viewer);
            all.push(...ids(page));
            cursor = page.nextCursor ?? undefined;
          } while (cursor);
          return all;
        })();
        // Alice ne voit plus les vidéos de Bob ; Bob, lui, voit les siennes et celles de Dave.
        if (viewer === 'alice') expect(seen.sort()).toEqual([...others].sort());
        else expect(seen.sort()).toEqual([...bobs, ...others].sort());
      }
      // Invité : rien n'est filtré.
      expect((await scrollAll(3)).flat()).toHaveLength(8);
    });

    it('complète la page avec les vidéos suivantes de l’ordre, sans en perdre ni en répéter', async () => {
      // Une vidéo de Bob parmi 4 : quelle que soit sa place, la première page de 3 d'Alice est pleine.
      const bobs = await publish('bob');
      const daves = await Promise.all(Array.from({ length: 3 }, () => publish('dave')));
      await interactions.setBlock('alice', 'bob', true);
      const first = await feed.getPage(undefined, 3, 'alice');
      expect(ids(first)).toHaveLength(3);
      expect(ids(first)).not.toContain(bobs);
      const rest = first.nextCursor ? ids(await feed.getPage(first.nextCursor, 3, 'alice')) : [];
      expect([...ids(first), ...rest].sort()).toEqual([...daves].sort());
    });

    it('bloqué par l’auteur : ses vidéos disparaissent aussi du feed du compte bloqué', async () => {
      await publish('alice');
      const daves = await publish('dave');
      await interactions.setBlock('alice', 'bob', true);
      expect(ids(await feed.getPage(undefined, 10, 'bob'))).toEqual([daves]);
    });

    it('débloquer fait revenir les vidéos', async () => {
      await publish('bob');
      await interactions.setBlock('alice', 'bob', true);
      expect(ids(await feed.getPage(undefined, 10, 'alice'))).toEqual([]);
      await interactions.setBlock('alice', 'bob', false);
      expect(ids(await feed.getPage(undefined, 10, 'alice'))).toHaveLength(1);
    });

    it('vidéo seule introuvable pour les deux comptes, visible pour les autres', async () => {
      const video = await publish('bob');
      await interactions.setBlock('bob', 'alice', true);
      await expect(feed.getItem(video, 'alice')).rejects.toBeInstanceOf(FeedItemNotFoundError);
      await expect(feed.getItem(video, 'dave')).resolves.toMatchObject({ video: { id: video } });
      await expect(feed.getItem(video, null)).resolves.toMatchObject({ video: { id: video } });
      await expect(feed.getItem(video, 'bob')).resolves.toMatchObject({ video: { id: video } });
    });

    it("grilles d'un compte bloqué vides, dans les deux sens ; un curseur invalide reste refusé", async () => {
      const bobs = await publish('bob');
      const alices = await publish('alice');
      await interactions.setReaction('bob', alices, 'repost', true);
      await interactions.setReaction('alice', bobs, 'repost', true);
      await interactions.setBlock('alice', 'bob', true);

      await expect(feed.listAuthorVideos('bob', undefined, 21, 'alice')).resolves.toEqual({ items: [], nextCursor: null });
      await expect(feed.listReposts('bob', undefined, 21, 'alice')).resolves.toEqual({ items: [], nextCursor: null });
      await expect(feed.listAuthorVideos('alice', undefined, 21, 'bob')).resolves.toEqual({ items: [], nextCursor: null });
      await expect(feed.listReposts('bob', 'pas-un-curseur', 21, 'alice')).rejects.toBeInstanceOf(InvalidFeedCursorError);
      // Ses propres grilles et celles des autres comptes restent lisibles ; en invité, rien n'est filtré.
      expect(ids(await feed.listAuthorVideos('bob', undefined, 21, 'bob'))).toEqual([bobs]);
      expect(ids(await feed.listAuthorVideos('bob', undefined, 21, 'dave'))).toEqual([bobs]);
      expect(ids(await feed.listAuthorVideos('bob', undefined, 21, null))).toEqual([bobs]);
    });

    it("retire les vidéos d'un compte bloqué des republications d'un tiers, des favoris, des likes et de l'historique", async () => {
      const bobs = await publish('bob');
      const daves = await publish('dave');
      for (const kind of ['repost', 'favorite', 'like'] as const) {
        await interactions.setReaction('dave', bobs, kind, true);
        await interactions.setReaction('alice', bobs, kind, true);
        await interactions.setReaction('alice', daves, kind, true);
      }
      await interactions.recordView('alice', bobs);
      await interactions.recordView('alice', daves);
      await interactions.setBlock('alice', 'bob', true);

      expect(ids(await feed.listReposts('dave', undefined, 21, 'alice'))).toEqual([]);
      expect(ids(await feed.listReposts('dave', undefined, 21, null))).toEqual([bobs]);
      expect(ids(await feed.listReposts('alice', undefined, 21, 'alice'))).toEqual([daves]);
      expect(ids(await feed.listFavorites('alice', undefined, 21))).toEqual([daves]);
      expect(ids(await feed.listLikes('alice', undefined, 21))).toEqual([daves]);
      expect(ids(await feed.listHistory('alice', undefined, 21))).toEqual([daves]);
    });
  });

  it('feed vide : aucune vidéo, pas de page suivante', async () => {
    await expect(feed.getPage(undefined, 10)).resolves.toEqual({ items: [], nextCursor: null });
  });

  it('un curseur valide encode photo, graine et position', () => {
    expect(encodeCursor({ snapshotId: 's', seed: 42, offset: 10 })).toBe(Buffer.from('{"s":"s","r":42,"o":10}').toString('base64url'));
  });
});

describe('seededShuffle', () => {
  const items = Array.from({ length: 50 }, (_, i) => i);

  it('est une permutation : mêmes éléments, aucun perdu ni dupliqué', () => {
    expect(seededShuffle(items, 7).sort((a, b) => a - b)).toEqual(items);
  });

  it('est déterministe pour une graine, et varie selon la graine', () => {
    expect(seededShuffle(items, 7)).toEqual(seededShuffle(items, 7));
    expect(seededShuffle(items, 7)).not.toEqual(seededShuffle(items, 8));
    expect(seededShuffle(items, 7)).not.toEqual(items);
  });
});

function decodeSeed(cursor: string): number {
  return (JSON.parse(Buffer.from(cursor, 'base64url').toString()) as { r: number }).r;
}
