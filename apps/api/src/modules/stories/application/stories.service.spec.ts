import { beforeEach, describe, expect, it } from 'vitest';
import { InMemoryRateLimiter } from '../../../rate-limit/in-memory-rate-limiter';
import { InMemorySuspendedAccounts } from '../../../suspension/in-memory-suspended-accounts';
import { InteractionsService } from '../../interactions/application/interactions.service';
import { InMemoryInteractionRepository } from '../../interactions/infrastructure/in-memory-interaction.repository';
import { InMemoryProfileCountersPublisher } from '../../interactions/infrastructure/in-memory-profile-counters-publisher';
import { NotificationsService } from '../../notifications/application/notifications.service';
import { InMemoryNotificationPublisher } from '../../notifications/infrastructure/in-memory-notification-publisher';
import { InMemoryNotificationRepository } from '../../notifications/infrastructure/in-memory-notification.repository';
import { UsersService } from '../../users/application/users.service';
import type { User } from '../../users/domain/user';
import { InMemoryAccountContentCleanup } from '../../users/infrastructure/in-memory-account-content-cleanup';
import { InMemoryAvatarStorage } from '../../users/infrastructure/in-memory-avatar-storage';
import { InMemoryUserRepository } from '../../users/infrastructure/in-memory-user.repository';
import { VideosService } from '../../videos/application/videos.service';
import { UPLOAD_RATE_LIMITS, uploadRateLimitKey } from '../../videos/domain/upload-rules';
import { TranscodingQueue } from '../../videos/domain/transcoding-queue';
import { InMemoryVideoCleanupQueue } from '../../videos/infrastructure/in-memory-video-cleanup-queue';
import { InMemoryVideoEventPublisher } from '../../videos/infrastructure/in-memory-video-event-publisher';
import { InMemoryVideoRepository } from '../../videos/infrastructure/in-memory-video.repository';
import { InMemoryVideoStorage } from '../../videos/infrastructure/in-memory-video-storage';
import { MAX_ACTIVE_STORIES, STORY_LIFETIME_MS } from '../domain/story';
import {
  InvalidStoryCursorError,
  InvalidStoryPhotoError,
  OwnStoryError,
  StoryAuthorNotFoundError,
  StoryNotAwaitingUploadError,
  StoryNotFoundError,
  StoryTooLargeError,
  StoryUploadIncompleteError,
  TooManyActiveStoriesError,
  TooManyStoryActionsError,
  UnsupportedStoryTypeError,
} from '../domain/story.errors';
import { STORY_CLEANUP_DELAY_MS } from '../domain/story-queues';
import { inMemoryStories, jpegHeader, publishTestStory } from '../infrastructure/in-memory-stories';

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

const HOUR = 3600 * 1000;

describe('StoriesService (ADR-051)', () => {
  let clock: Date;
  let suspended: InMemorySuspendedAccounts;
  let interactions: InteractionsService;
  let users: UsersService;
  let stories: ReturnType<typeof inMemoryStories>;

  const advance = (ms: number) => (clock = new Date(clock.getTime() + ms));
  const publish = (userId: string, mediaType: 'photo' | 'video' = 'photo') => publishTestStory(stories, userId, mediaType);

  beforeEach(() => {
    clock = new Date('2026-10-08T10:00:00Z');
    suspended = new InMemorySuspendedAccounts();
    const userRepository = new InMemoryUserRepository(['alice', 'bob', 'carol', 'dave'].map(user));
    const videoRepository = new InMemoryVideoRepository();
    users = new UsersService(userRepository, new InMemoryAvatarStorage(), new InMemoryAccountContentCleanup(), suspended);
    const videos = new VideosService(
      videoRepository,
      new InMemoryVideoStorage(),
      new NoopTranscodingQueue(),
      new InMemoryVideoEventPublisher(),
      new InMemoryVideoCleanupQueue(),
      new InMemoryRateLimiter(),
    );
    const notifications = new NotificationsService(
      new InMemoryNotificationRepository(),
      users,
      videos,
      new InMemoryNotificationPublisher(),
      suspended,
    );
    interactions = new InteractionsService(
      new InMemoryInteractionRepository(videoRepository, userRepository),
      videos,
      users,
      notifications,
      new InMemoryRateLimiter(),
      suspended,
      new InMemoryProfileCountersPublisher(),
    );
    stories = inMemoryStories(users, interactions, () => clock);
  });

  describe('publication', () => {
    it('photo : envoi multipart dans le bucket des médias, vérifiée puis publiée 24 h, expiration programmée', async () => {
      const upload = await stories.service.createUpload('alice', { contentType: 'image/jpeg', fileSize: 1000 });
      expect(upload.story).toMatchObject({ userId: 'alice', mediaType: 'photo', status: 'uploading', publishedAt: null });
      expect(upload.story.rawKey).toBe(`${upload.story.id}/photo.jpg`);
      expect(upload.parts).toHaveLength(1);
      expect(upload.parts[0].url).toContain('memory://media/');

      stories.storage.contents.set(upload.story.rawKey, jpegHeader(1080, 1920));
      const etag = stories.storage.putPart(upload.story.uploadId!, 1, 1000);
      const story = await stories.service.completeUpload('alice', upload.story.id, [{ partNumber: 1, etag }]);

      expect(story).toMatchObject({
        status: 'ready',
        uploadId: null,
        mediaUrl: `https://cdn.test/${upload.story.id}/photo.jpg`,
        thumbnailUrl: `https://cdn.test/${upload.story.id}/photo.jpg`,
        publishedAt: clock,
        expiresAt: new Date(clock.getTime() + STORY_LIFETIME_MS),
      });
      expect(stories.lifecycle.expiries.get(story.id)).toEqual(story.expiresAt);
      expect(stories.transcoding.jobs).toEqual([]);
    });

    it('photo refusée (pas 9:16, pas un JPEG, trop petite) : supprimée, story en échec', async () => {
      for (const content of [jpegHeader(1080, 1080), new Uint8Array([0x89, 0x50, 0x4e, 0x47]), jpegHeader(270, 480), jpegHeader(1440, 2560)]) {
        const upload = await stories.service.createUpload('alice', { contentType: 'image/jpeg', fileSize: 500 });
        stories.storage.contents.set(upload.story.rawKey, content);
        const etag = stories.storage.putPart(upload.story.uploadId!, 1, 500);
        await expect(stories.service.completeUpload('alice', upload.story.id, [{ partNumber: 1, etag }])).rejects.toThrow(InvalidStoryPhotoError);
        expect((await stories.repository.findById(upload.story.id))?.status).toBe('failed');
        await expect(stories.storage.getObjectSize('media', upload.story.rawKey)).resolves.toBeNull();
      }
    });

    it('vidéo : brut sous le préfixe de l’auteur, transcodage, puis publiée et annoncée ; résultat en double ignoré', async () => {
      const upload = await stories.service.createUpload('alice', { contentType: 'video/quicktime', fileSize: 25 * 1024 * 1024 });
      expect(upload.story.rawKey).toBe(`alice/stories/${upload.story.id}.mov`);
      expect(upload.parts).toHaveLength(3);
      const parts = [1, 2, 3].map((partNumber) => ({
        partNumber,
        etag: stories.storage.putPart(upload.story.uploadId!, partNumber, partNumber < 3 ? 10 * 1024 * 1024 : 5 * 1024 * 1024),
      }));
      const processing = await stories.service.completeUpload('alice', upload.story.id, parts);
      expect(processing).toMatchObject({ status: 'processing', uploadId: null, expiresAt: null });
      expect(stories.transcoding.jobs).toEqual([{ storyId: upload.story.id, rawKey: upload.story.rawKey }]);

      advance(30_000);
      const outcome = { status: 'ready' as const, mediaUrl: 'https://cdn.test/s/master.m3u8', thumbnailUrl: 'https://cdn.test/s/thumbnail.jpg' };
      await expect(stories.service.applyTranscodeResult(upload.story.id, outcome)).resolves.toBe(true);
      const story = await stories.repository.findById(upload.story.id);
      // Visible 24 h après la publication, pas après le début de l'envoi.
      expect(story).toMatchObject({ status: 'ready', publishedAt: clock, expiresAt: new Date(clock.getTime() + STORY_LIFETIME_MS) });
      expect(stories.events.processed.map((s) => s.status)).toEqual(['ready']);
      expect(stories.lifecycle.expiries.has(upload.story.id)).toBe(true);

      await expect(stories.service.applyTranscodeResult(upload.story.id, outcome)).resolves.toBe(false);
      expect(stories.events.processed).toHaveLength(1);
    });

    it('vidéo en échec : annoncée, jamais visible ; résultat d’une story supprimée : fichiers nettoyés', async () => {
      const upload = await stories.service.createUpload('alice', { contentType: 'video/mp4', fileSize: 100 });
      const etag = stories.storage.putPart(upload.story.uploadId!, 1, 100);
      await stories.service.completeUpload('alice', upload.story.id, [{ partNumber: 1, etag }]);
      await stories.service.applyTranscodeResult(upload.story.id, { status: 'failed' });
      expect(stories.events.processed.map((s) => s.status)).toEqual(['failed']);
      await expect(stories.service.getStory(upload.story.id, 'bob')).rejects.toThrow(StoryNotFoundError);
      await expect(stories.service.getStory(upload.story.id, 'alice')).resolves.toMatchObject({ status: 'failed' });

      await expect(stories.service.applyTranscodeResult('00000000-0000-7000-8000-999999999999', { status: 'failed' })).resolves.toBe(false);
      expect(stories.lifecycle.cleanups.at(-1)).toEqual({
        files: { storyId: '00000000-0000-7000-8000-999999999999', mediaType: 'video', rawKey: null, uploadId: null },
        delayMs: 0,
      });
    });

    it('refuse format, taille et envoi incomplet ; confirmation en double : 409', async () => {
      await expect(stories.service.createUpload('alice', { contentType: 'image/png', fileSize: 10 })).rejects.toThrow(UnsupportedStoryTypeError);
      await expect(stories.service.createUpload('alice', { contentType: 'image/jpeg', fileSize: 6 * 1024 * 1024 })).rejects.toThrow(
        StoryTooLargeError,
      );

      const upload = await stories.service.createUpload('alice', { contentType: 'video/mp4', fileSize: 25 * 1024 * 1024 });
      const etag = stories.storage.putPart(upload.story.uploadId!, 1, 10 * 1024 * 1024);
      await expect(stories.service.completeUpload('alice', upload.story.id, [{ partNumber: 1, etag }])).rejects.toThrow(StoryUploadIncompleteError);
      await expect(stories.service.completeUpload('bob', upload.story.id, [])).rejects.toThrow(StoryNotFoundError);

      const story = await publish('alice');
      await expect(stories.service.completeUpload('alice', story.id, [])).rejects.toThrow(StoryNotAwaitingUploadError);
    });

    it('30 stories actives au plus (envois en cours compris) ; une story expirée libère une place', async () => {
      for (let i = 0; i < MAX_ACTIVE_STORIES; i++)
        await stories.repository.create({ id: `s${i}`, userId: 'alice', mediaType: 'photo', rawKey: `k${i}`, uploadId: 'u', rawSize: 1 });
      await expect(stories.service.createUpload('alice', { contentType: 'image/jpeg', fileSize: 10 })).rejects.toThrow(TooManyActiveStoriesError);
      await stories.repository.markFailed('s0');
      await expect(stories.service.createUpload('alice', { contentType: 'image/jpeg', fileSize: 10 })).resolves.toBeDefined();
    });

    it('limites de débit : photos à part, une story vidéo compte dans la limite des vidéos (ADR-039)', async () => {
      for (let i = 0; i < 20; i++) await stories.service.createUpload('alice', { contentType: 'image/jpeg', fileSize: 10 });
      await expect(stories.service.createUpload('alice', { contentType: 'image/jpeg', fileSize: 10 })).rejects.toThrow(TooManyStoryActionsError);

      for (let i = 0; i < UPLOAD_RATE_LIMITS[0].limit; i++) await stories.rateLimiter.consume(uploadRateLimitKey('bob'), UPLOAD_RATE_LIMITS);
      const error = await stories.service.createUpload('bob', { contentType: 'video/mp4', fileSize: 10 }).catch((e: unknown) => e);
      expect(error).toBeInstanceOf(TooManyStoryActionsError);
      expect((error as TooManyStoryActionsError).retryAfterSeconds).toBeGreaterThan(0);
    });

    it('expiration non programmée (Redis indisponible) : la publication réussit quand même', async () => {
      stories.lifecycle.failExpiry = true;
      await expect(publish('alice')).resolves.toMatchObject({ status: 'ready' });
    });
  });

  describe('lecture', () => {
    it('stories d’un compte, de la plus ancienne à la plus récente ; état du lecteur, chiffres de l’auteur, rien d’expiré', async () => {
      const first = await publish('alice');
      advance(HOUR);
      const second = await publish('alice', 'video');
      await stories.service.recordView('bob', first.id);
      await stories.service.setLiked('carol', first.id, true);

      const guest = await stories.service.listUserStories('alice', null);
      expect(guest.items.map((i) => [i.story.id, i.viewer, i.stats])).toEqual([
        [first.id, undefined, undefined],
        [second.id, undefined, undefined],
      ]);
      const bob = await stories.service.listUserStories('alice', 'bob');
      expect(bob.items.map((i) => i.viewer)).toEqual([
        { viewed: true, liked: false },
        { viewed: false, liked: false },
      ]);
      const own = await stories.service.listUserStories('alice', 'alice');
      expect(own.items.map((i) => i.stats)).toEqual([
        { viewersCount: 2, likesCount: 1 },
        { viewersCount: 0, likesCount: 0 },
      ]);

      // La première expire (job en retard ou non) : elle ne se voit plus nulle part.
      advance(STORY_LIFETIME_MS - HOUR);
      expect((await stories.service.listUserStories('alice', 'bob')).items.map((i) => i.story.id)).toEqual([second.id]);
      await expect(stories.service.getStory(first.id, 'bob')).rejects.toThrow(StoryNotFoundError);
      await expect(stories.service.recordView('bob', first.id)).rejects.toThrow(StoryNotFoundError);
      await expect(stories.service.listUserStories('inconnu', null)).rejects.toThrow(StoryAuthorNotFoundError);
    });

    it('masquées pour un compte bloqué (dans les deux sens) et pour tous si l’auteur est suspendu', async () => {
      const story = await publish('alice');
      await interactions.setBlock('alice', 'bob', true);
      expect((await stories.service.listUserStories('alice', 'bob')).items).toEqual([]);
      await expect(stories.service.getVisibleStory('bob', story.id)).rejects.toThrow(StoryNotFoundError);
      expect((await stories.service.listUserStories('alice', 'carol')).items).toHaveLength(1);

      await suspended.add('alice');
      expect((await stories.service.listUserStories('alice', null)).items).toEqual([]);
      await expect(stories.service.getStory(story.id, 'carol')).rejects.toThrow(StoryNotFoundError);
    });

    it('rangée : soi d’abord, puis les abonnements avec des stories à voir, puis du plus récent au plus ancien', async () => {
      for (const target of ['bob', 'carol', 'dave']) await interactions.setFollow('alice', target, true);
      const bobStory = await publish('bob');
      advance(HOUR);
      await publish('carol');
      advance(HOUR);
      await publish('dave');
      advance(HOUR);
      await publish('alice');
      // Une story d'un compte non suivi n'apparaît pas.
      await interactions.setFollow('alice', 'dave', false);
      await stories.service.recordView('alice', bobStory.id);

      let tray = await stories.service.getTray('alice');
      expect(tray.map((e) => [e.user.id, e.hasUnseen, e.storiesCount])).toEqual([
        ['alice', false, 1],
        ['carol', true, 1],
        ['bob', false, 1],
      ]);

      // Une nouvelle story de bob le remet parmi les comptes à voir, en tête (plus récent).
      advance(HOUR);
      await publish('bob');
      tray = await stories.service.getTray('alice');
      expect(tray.map((e) => [e.user.id, e.hasUnseen, e.storiesCount])).toEqual([
        ['alice', false, 1],
        ['bob', true, 2],
        ['carol', true, 1],
      ]);
    });

    it('anneau du feed : auteurs avec une story visible, et s’il en reste à voir', async () => {
      const story = await publish('bob');
      await publish('carol');
      await interactions.setBlock('carol', 'alice', true);
      const rings = await stories.service.getStoryRings(['bob', 'carol', 'dave', 'bob'], 'alice');
      expect([...rings.entries()]).toEqual([['bob', { hasUnseen: true }]]);
      await stories.service.recordView('alice', story.id);
      expect((await stories.service.getStoryRings(['bob'], 'alice')).get('bob')).toEqual({ hasUnseen: false });
      expect((await stories.service.getStoryRings(['bob'], null)).get('bob')).toEqual({ hasUnseen: true });
      expect((await stories.service.getStoryRings(['bob'], 'bob')).get('bob')).toEqual({ hasUnseen: false });
    });
  });

  describe('vues et likes', () => {
    it('vue : première date gardée, sa propre story ignorée, au-delà de la limite ignorée sans erreur', async () => {
      const story = await publish('alice');
      await stories.service.recordView('bob', story.id);
      advance(60_000);
      await stories.service.recordView('bob', story.id);
      await stories.service.recordView('alice', story.id);
      expect(stories.repository.views).toEqual([{ storyId: story.id, userId: 'bob', viewedAt: new Date(clock.getTime() - 60_000), likedAt: null }]);

      for (let i = 0; i < 600; i++) await stories.rateLimiter.consume('story-view:carol', [{ limit: 600, windowSeconds: 3600 }]);
      await stories.service.recordView('carol', story.id);
      expect(stories.repository.views).toHaveLength(1);
    });

    it('like : vaut vue, idempotent, retiré ; pas sur sa propre story ; limite (429)', async () => {
      const story = await publish('alice');
      await stories.service.setLiked('bob', story.id, true);
      await stories.service.setLiked('bob', story.id, true);
      expect(stories.repository.views).toEqual([{ storyId: story.id, userId: 'bob', viewedAt: clock, likedAt: clock }]);
      await stories.service.setLiked('bob', story.id, false);
      expect(stories.repository.views[0].likedAt).toBeNull();
      await expect(stories.service.setLiked('alice', story.id, true)).rejects.toThrow(OwnStoryError);

      for (let i = 0; i < 60; i++) await stories.rateLimiter.consume('story-like:carol', [{ limit: 60, windowSeconds: 60 }]);
      await expect(stories.service.setLiked('carol', story.id, true)).rejects.toThrow(TooManyStoryActionsError);
      // Retirer reste possible.
      await expect(stories.service.setLiked('carol', story.id, false)).resolves.toBeUndefined();
    });

    it('liste des personnes qui l’ont vue : auteur seulement, paginée, comptes masqués retirés', async () => {
      const story = await publish('alice');
      for (const viewer of ['bob', 'carol', 'dave']) {
        await stories.service.recordView(viewer, story.id);
        advance(1000);
      }
      await stories.service.setLiked('carol', story.id, true);

      const first = await stories.service.listViewers('alice', story.id, undefined, 2);
      expect(first.items.map((i) => [i.user.id, i.liked])).toEqual([
        ['dave', false],
        ['carol', true],
      ]);
      expect([first.viewersCount, first.likesCount]).toEqual([3, 1]);
      const second = await stories.service.listViewers('alice', story.id, first.nextCursor!, 2);
      expect(second.items.map((i) => i.user.id)).toEqual(['bob']);
      expect(second.nextCursor).toBeNull();

      await interactions.setBlock('alice', 'carol', true);
      const afterBlock = await stories.service.listViewers('alice', story.id, undefined, 10);
      expect(afterBlock.items.map((i) => i.user.id)).toEqual(['dave', 'bob']);
      expect([afterBlock.viewersCount, afterBlock.likesCount]).toEqual([2, 0]);

      await expect(stories.service.listViewers('bob', story.id, undefined, 10)).rejects.toThrow(StoryNotFoundError);
      await expect(stories.service.listViewers('alice', story.id, 'nimporte', 10)).rejects.toThrow(InvalidStoryCursorError);
    });
  });

  describe('suppression et expiration', () => {
    it('par son auteur : nettoyage programmé avant la suppression, vues emportées ; pas par un autre', async () => {
      const story = await publish('alice');
      await stories.service.recordView('bob', story.id);
      await expect(stories.service.deleteStory('bob', story.id)).rejects.toThrow(StoryNotFoundError);
      await stories.service.deleteStory('alice', story.id);
      expect(stories.lifecycle.cleanups).toEqual([
        { files: { storyId: story.id, mediaType: 'photo', rawKey: story.rawKey, uploadId: null }, delayMs: STORY_CLEANUP_DELAY_MS },
      ]);
      await expect(stories.repository.findById(story.id)).resolves.toBeNull();
      expect(stories.repository.views).toEqual([]);
    });

    it('job d’échéance : rien avant l’heure, suppression après ; nettoyage des fichiers une fois la story partie', async () => {
      const story = await publish('alice');
      await expect(stories.service.expire(story.id)).resolves.toBe(false);
      await expect(stories.service.cleanupFiles({ storyId: story.id, mediaType: 'photo', rawKey: story.rawKey, uploadId: null })).resolves.toBe(
        false,
      );

      advance(STORY_LIFETIME_MS);
      await expect(stories.service.expire(story.id)).resolves.toBe(true);
      await expect(stories.service.expire(story.id)).resolves.toBe(false);
      expect(await stories.storage.getObjectSize('media', story.rawKey)).toBe(1000);
      await expect(stories.service.cleanupFiles(stories.lifecycle.cleanups[0].files)).resolves.toBe(true);
      expect(await stories.storage.getObjectSize('media', story.rawKey)).toBeNull();
    });

    it('nettoyage d’une story vidéo : upload annulé, brut et fichiers HLS supprimés', async () => {
      const video = await publish('alice', 'video');
      stories.storage.mediaFiles.add(`${video.id}/master.m3u8`);
      await stories.service.deleteStory('alice', video.id);
      await stories.service.cleanupFiles(stories.lifecycle.cleanups[0].files);
      expect(await stories.storage.getObjectSize('raw', video.rawKey)).toBeNull();
      expect(stories.storage.mediaFiles.size).toBe(0);
    });

    it('maintenance : stories expirées, non publiées depuis 24 h, transcodages bloqués relancés', async () => {
      const photo = await publish('alice');
      const abandoned = await stories.service.createUpload('bob', { contentType: 'image/jpeg', fileSize: 10 });
      const stuck = await stories.service.createUpload('carol', { contentType: 'video/mp4', fileSize: 10 });
      await stories.service.completeUpload('carol', stuck.story.id, [{ partNumber: 1, etag: stories.storage.putPart(stuck.story.uploadId!, 1, 10) }]);
      stories.transcoding.jobs.length = 0;

      advance(2 * HOUR);
      expect(await stories.service.runMaintenance()).toEqual({ expired: 0, purged: 0, requeued: 1 });
      expect(stories.transcoding.jobs.map((j) => j.storyId)).toEqual([stuck.story.id]);

      advance(STORY_LIFETIME_MS);
      expect(await stories.service.runMaintenance()).toEqual({ expired: 1, purged: 2, requeued: 0 });
      for (const id of [photo.id, abandoned.story.id, stuck.story.id]) await expect(stories.repository.findById(id)).resolves.toBeNull();
      // Envoi abandonné : l'upload multipart est annulé par le nettoyage.
      expect(stories.lifecycle.cleanups.some((c) => c.files.storyId === abandoned.story.id && c.files.uploadId !== null)).toBe(true);
      expect(stories.transcoding.cancelled).toContain(stuck.story.id);
    });

    it('suppression du compte : nettoyage de toutes ses stories programmé (écouteur de UsersService)', async () => {
      await publish('alice');
      await publish('alice', 'video');
      await expect(stories.service.scheduleAuthorFilesCleanup('alice')).resolves.toBe(2);
      expect(stories.lifecycle.cleanups.map((c) => c.files.mediaType)).toEqual(['photo', 'video']);
      await expect(stories.service.scheduleAuthorFilesCleanup('bob')).resolves.toBe(0);
    });
  });
});
