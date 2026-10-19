import { InMemoryRateLimiter } from '../../../rate-limit/in-memory-rate-limiter';
import { beforeEach, describe, expect, it } from 'vitest';
import { CLEANUP_DELAY_MS } from '../domain/cleanup-queue';
import { TranscodingQueue, type TranscodingJob } from '../domain/transcoding-queue';
import { MAX_VIDEO_SIZE_BYTES, UPLOAD_PART_SIZE_BYTES } from '../domain/upload-rules';
import {
  InvalidHashtagError,
  TooManyUploadsError,
  UnsupportedVideoTypeError,
  UploadIncompleteError,
  VideoNotAwaitingUploadError,
  VideoNotFoundError,
  VideoTooLargeError,
} from '../domain/video.errors';
import { InMemoryVideoCleanupQueue } from '../infrastructure/in-memory-video-cleanup-queue';
import { InMemoryVideoEventPublisher } from '../infrastructure/in-memory-video-event-publisher';
import { InMemoryVideoRepository } from '../infrastructure/in-memory-video.repository';
import { InMemoryVideoStorage } from '../infrastructure/in-memory-video-storage';
import { VideosService } from './videos.service';

class RecordingTranscodingQueue extends TranscodingQueue {
  readonly jobs: TranscodingJob[] = [];
  readonly cancelled: string[] = [];
  async enqueue(job: TranscodingJob) {
    this.jobs.push(job);
  }
  async cancel(videoId: string) {
    this.cancelled.push(videoId);
  }
}

const ALICE = 'alice-id';
const BOB = 'bob-id';
const MIB = 1024 ** 2;

describe('VideosService', () => {
  let videos: InMemoryVideoRepository;
  let storage: InMemoryVideoStorage;
  let queue: RecordingTranscodingQueue;
  let events: InMemoryVideoEventPublisher;
  let cleanup: InMemoryVideoCleanupQueue;
  let service: VideosService;

  beforeEach(() => {
    videos = new InMemoryVideoRepository();
    storage = new InMemoryVideoStorage();
    queue = new RecordingTranscodingQueue();
    events = new InMemoryVideoEventPublisher();
    cleanup = new InMemoryVideoCleanupQueue();
    service = new VideosService(videos, storage, queue, events, cleanup, new InMemoryRateLimiter(), () => new Date('2026-01-01T00:00:00Z'));
  });

  // Ce que fait l'app : envoie chaque partie sur son URL et collecte les ETags.
  function uploadAllParts(uploadId: string, fileSize: number, partCount: number) {
    return Array.from({ length: partCount }, (_, i) => {
      const size = i < partCount - 1 ? UPLOAD_PART_SIZE_BYTES : fileSize - UPLOAD_PART_SIZE_BYTES * (partCount - 1);
      return { partNumber: i + 1, etag: storage.putPart(uploadId, i + 1, size) };
    });
  }

  describe('createUpload', () => {
    it('crée la vidéo en uploading et découpe le fichier en parties de 10 Mio', async () => {
      const upload = await service.createUpload(ALICE, { contentType: 'video/quicktime', fileSize: 25 * MIB, description: '  Ma vidéo  ' });

      expect(upload.video).toMatchObject({ userId: ALICE, status: 'uploading', description: 'Ma vidéo' });
      expect(upload.video.rawKey).toMatch(new RegExp(`^${ALICE}/[0-9a-f-]{36}\\.mov$`));
      expect(upload.parts.map((p) => p.partNumber)).toEqual([1, 2, 3]);
      expect(upload.partSize).toBe(10 * MIB);
      expect(upload.expiresAt).toEqual(new Date('2026-01-01T02:00:00Z'));
    });

    it('utilise une seule partie pour un petit fichier', async () => {
      const upload = await service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: 1000 });
      expect(upload.parts).toHaveLength(1);
      expect(upload.video.description).toBeNull();
    });

    it('refuse un format non pris en charge ou un fichier trop volumineux', async () => {
      await expect(service.createUpload(ALICE, { contentType: 'image/png', fileSize: 1000 })).rejects.toBeInstanceOf(UnsupportedVideoTypeError);
      await expect(service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: MAX_VIDEO_SIZE_BYTES + 1 })).rejects.toBeInstanceOf(
        VideoTooLargeError,
      );
      expect(videos.videos.size).toBe(0);
      expect(storage.uploads.size).toBe(0);
    });

    it('limite les envois démarrés (ADR-039) : 10 par heure et 30 par jour ; une requête invalide ne compte pas', async () => {
      let clock = Date.UTC(2026, 0, 1);
      service = new VideosService(videos, storage, queue, events, cleanup, new InMemoryRateLimiter(() => clock));
      await expect(service.createUpload(ALICE, { contentType: 'image/png', fileSize: 1000 })).rejects.toBeInstanceOf(UnsupportedVideoTypeError);
      for (let i = 0; i < 10; i++) await service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: 1000 });
      const refused = await service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: 1000 }).catch((e: unknown) => e);
      expect(refused).toBeInstanceOf(TooManyUploadsError);
      expect((refused as TooManyUploadsError).retryAfterSeconds).toBe(3600);
      expect((refused as TooManyUploadsError).message).toBe('Trop de vidéos envoyées récemment : réessayez dans 1 h');
      expect(videos.videos.size).toBe(10);
      // Un autre compte n'est pas touché.
      await expect(service.createUpload('0192f3a0-0000-7000-8000-0000000000bb', { contentType: 'video/mp4', fileSize: 1000 })).resolves.toBeDefined();

      // Heures suivantes : 10 de plus chacune, jusqu'à 30 dans la journée.
      for (const hour of [1, 2]) {
        clock = Date.UTC(2026, 0, 1, hour);
        for (let i = 0; i < 10; i++) await service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: 1000 });
      }
      clock = Date.UTC(2026, 0, 1, 3);
      const daily = await service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: 1000 }).catch((e: unknown) => e);
      expect((daily as TooManyUploadsError).retryAfterSeconds).toBe(21 * 3600);
      expect((daily as TooManyUploadsError).message).toBe('Trop de vidéos envoyées récemment : réessayez dans 21 h');
    });
  });

  describe('completeUpload', () => {
    it('assemble les parties, passe la vidéo en processing et lance le transcodage', async () => {
      const { video, parts } = await service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: 25 * MIB });
      const uploaded = uploadAllParts(video.uploadId!, 25 * MIB, parts.length);

      const result = await service.completeUpload(ALICE, video.id, uploaded.reverse());

      expect(result).toMatchObject({ status: 'processing', uploadId: null });
      expect(storage.objects.get(video.rawKey)).toBe(25 * MIB);
      expect(queue.jobs).toEqual([{ videoId: video.id, rawKey: video.rawKey }]);
    });

    it('refuse un upload incomplet sans changer la vidéo, puis accepte après renvoi de la partie', async () => {
      const { video } = await service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: 25 * MIB });
      const [first, second] = uploadAllParts(video.uploadId!, 25 * MIB, 3);
      const third = { partNumber: 3, etag: '"etag-jamais-recu"' };

      await expect(service.completeUpload(ALICE, video.id, [first, second, third])).rejects.toBeInstanceOf(UploadIncompleteError);
      expect((await videos.findById(video.id))!.status).toBe('uploading');

      const resent = { partNumber: 3, etag: storage.putPart(video.uploadId!, 3, 5 * MIB) };
      await expect(service.completeUpload(ALICE, video.id, [first, second, resent])).resolves.toMatchObject({ status: 'processing' });
    });

    // S3 assemble n'importe quel sous-ensemble des parties envoyées : sans ce contrôle,
    // une vidéo tronquée serait acceptée.
    it('refuse une confirmation qui omet des parties, même toutes envoyées', async () => {
      const { video } = await service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: 25 * MIB });
      const parts = uploadAllParts(video.uploadId!, 25 * MIB, 3);

      await expect(service.completeUpload(ALICE, video.id, parts.slice(0, 2))).rejects.toBeInstanceOf(UploadIncompleteError);
      await expect(service.completeUpload(ALICE, video.id, [parts[0], parts[0], parts[2]])).rejects.toBeInstanceOf(UploadIncompleteError);
      expect(storage.objects.has(video.rawKey)).toBe(false);
      await expect(service.completeUpload(ALICE, video.id, parts)).resolves.toMatchObject({ status: 'processing' });
    });

    it("passe la vidéo en failed si le fichier assemblé n'a pas la taille déclarée", async () => {
      const { video } = await service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: 1000 });
      const parts = [{ partNumber: 1, etag: storage.putPart(video.uploadId!, 1, 999) }];

      await expect(service.completeUpload(ALICE, video.id, parts)).rejects.toBeInstanceOf(UploadIncompleteError);
      expect(storage.objects.has(video.rawKey)).toBe(false);
      expect((await videos.findById(video.id))!.status).toBe('failed');
    });

    it("reprend si l'assemblage a déjà réussi mais que la vidéo n'a pas été mise à jour", async () => {
      const { video } = await service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: 1000 });
      const parts = uploadAllParts(video.uploadId!, 1000, 1);
      await storage.completeMultipartUpload(video.rawKey, video.uploadId!, parts); // réponse perdue côté app

      await expect(service.completeUpload(ALICE, video.id, parts)).resolves.toMatchObject({ status: 'processing' });
      expect(queue.jobs).toHaveLength(1);
    });

    it('refuse une seconde confirmation', async () => {
      const { video } = await service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: 1000 });
      const parts = uploadAllParts(video.uploadId!, 1000, 1);
      await service.completeUpload(ALICE, video.id, parts);

      await expect(service.completeUpload(ALICE, video.id, parts)).rejects.toBeInstanceOf(VideoNotAwaitingUploadError);
      expect(queue.jobs).toHaveLength(1);
    });

    it("traite la vidéo d'un autre utilisateur comme inexistante", async () => {
      const { video } = await service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: 1000 });
      const parts = uploadAllParts(video.uploadId!, 1000, 1);

      await expect(service.completeUpload(BOB, video.id, parts)).rejects.toBeInstanceOf(VideoNotFoundError);
      await expect(service.completeUpload(ALICE, 'inconnue', parts)).rejects.toBeInstanceOf(VideoNotFoundError);
    });

    it('supprime le fichier et passe la vidéo en failed si le client envoie plus que déclaré (au-delà de la limite)', async () => {
      // Les URLs signées ne bornent pas la taille des parties : un client peut envoyer plus que déclaré.
      const { video } = await service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: 1000 });
      const parts = [{ partNumber: 1, etag: storage.putPart(video.uploadId!, 1, MAX_VIDEO_SIZE_BYTES + 1) }];

      await expect(service.completeUpload(ALICE, video.id, parts)).rejects.toBeInstanceOf(UploadIncompleteError);
      expect(storage.objects.has(video.rawKey)).toBe(false);
      expect((await videos.findById(video.id))!.status).toBe('failed');
      expect(queue.jobs).toHaveLength(0);
    });
  });

  describe('applyTranscodeResult', () => {
    async function processingVideo() {
      const { video } = await service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: 1000 });
      await service.completeUpload(ALICE, video.id, uploadAllParts(video.uploadId!, 1000, 1));
      return video;
    }

    it('rend la vidéo publique quand le transcodage réussit', async () => {
      const video = await processingVideo();
      const applied = await service.applyTranscodeResult(video.id, {
        status: 'ready',
        hlsUrl: 'https://cdn/v.m3u8',
        thumbnailUrl: 'https://cdn/t.jpg',
      });

      expect(applied).toBe(true);
      await expect(service.getVideo(video.id, null)).resolves.toMatchObject({ status: 'ready', hlsUrl: 'https://cdn/v.m3u8' });
      expect(events.processed).toEqual([
        expect.objectContaining({ id: video.id, userId: ALICE, status: 'ready', thumbnailUrl: 'https://cdn/t.jpg' }),
      ]);
    });

    it('passe la vidéo en failed après un échec définitif', async () => {
      const video = await processingVideo();
      await service.applyTranscodeResult(video.id, { status: 'failed' });
      expect((await videos.findById(video.id))!.status).toBe('failed');
      expect(events.processed.map((v) => v.status)).toEqual(['failed']);
    });

    it('ignore un résultat en double ou pour une vidéo qui n’est pas en processing', async () => {
      const video = await processingVideo();
      await service.applyTranscodeResult(video.id, { status: 'ready', hlsUrl: 'a', thumbnailUrl: 'b' });

      await expect(service.applyTranscodeResult(video.id, { status: 'failed' })).resolves.toBe(false);
      expect((await videos.findById(video.id))!.status).toBe('ready');
      await expect(service.applyTranscodeResult('inconnue', { status: 'failed' })).resolves.toBe(false);
      // L'auteur n'est prévenu qu'une fois, pour le résultat appliqué.
      expect(events.processed.map((v) => v.status)).toEqual(['ready']);
      // Vidéo encore en base : aucun nettoyage.
      expect(cleanup.scheduled.map((s) => s.cleanup.videoId)).toEqual(['inconnue']);
    });

    it('programme le nettoyage des fichiers publiés pour une vidéo supprimée pendant le transcodage', async () => {
      const video = await processingVideo();
      await service.deleteVideo(ALICE, video.id);
      cleanup.scheduled.length = 0;

      await expect(service.applyTranscodeResult(video.id, { status: 'ready', hlsUrl: 'a', thumbnailUrl: 'b' })).resolves.toBe(false);
      expect(cleanup.scheduled).toEqual([{ cleanup: { videoId: video.id, rawKey: null, uploadId: null }, delayMs: 0 }]);
      expect(events.processed).toHaveLength(0);
    });
  });

  describe('hashtags (ADR-049)', () => {
    // Vidéo envoyée avec `description`, puis transcodée avec `outcome`.
    async function transcoded(description: string, outcome: 'ready' | 'failed' = 'ready', userId = ALICE) {
      const { video } = await service.createUpload(userId, { contentType: 'video/mp4', fileSize: 1000, description });
      await service.completeUpload(userId, video.id, uploadAllParts(video.uploadId!, 1000, 1));
      await service.applyTranscodeResult(video.id, outcome === 'ready' ? { status: 'ready', hlsUrl: 'a', thumbnailUrl: 'b' } : { status: 'failed' });
      return video.id;
    }

    it('extrait les hashtags d’une vidéo publiée, pas d’une vidéo en échec ni en traitement', async () => {
      await transcoded('Coucher de soleil #Été #plage');
      await transcoded('#été encore');
      await transcoded('#raté', 'failed');
      const { video } = await service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: 1000, description: '#attente' });
      await service.completeUpload(ALICE, video.id, uploadAllParts(video.uploadId!, 1000, 1));

      await expect(service.getHashtag('#ÉTÉ')).resolves.toEqual({ name: 'été', videosCount: 2 });
      await expect(service.getHashtag('plage')).resolves.toEqual({ name: 'plage', videosCount: 1 });
      await expect(service.getHashtag('raté')).resolves.toEqual({ name: 'raté', videosCount: 0 });
      await expect(service.getHashtag('attente')).resolves.toEqual({ name: 'attente', videosCount: 0 });
      await expect(service.getHashtag('pas valide')).rejects.toBeInstanceOf(InvalidHashtagError);
    });

    it('cherche par début de nom, du plus utilisé au moins utilisé ; une vidéo supprimée ne compte plus', async () => {
      await transcoded('#plage #plongée');
      const removed = await transcoded('#plongée #pl_');
      await transcoded('#plongée');
      await transcoded('#pluie');

      await expect(service.searchHashtags('#PL', 10)).resolves.toEqual([
        { name: 'plongée', videosCount: 3 },
        { name: 'pl_', videosCount: 1 },
        { name: 'plage', videosCount: 1 },
        { name: 'pluie', videosCount: 1 },
      ]);
      await expect(service.searchHashtags('pl', 2)).resolves.toHaveLength(2);
      await expect(service.searchHashtags('#', 10)).resolves.toEqual([]);
      await expect(service.searchHashtags('a b', 10)).resolves.toEqual([]);

      await service.deleteVideo(ALICE, removed);
      await expect(service.searchHashtags('pl', 10)).resolves.toEqual([
        { name: 'plongée', videosCount: 2 },
        { name: 'plage', videosCount: 1 },
        { name: 'pluie', videosCount: 1 },
      ]);
    });

    it('liste les vidéos d’un hashtag de la plus récemment publiée à la plus ancienne, par pages', async () => {
      // Dates de publication strictement croissantes (les identifiants en mémoire ne sont pas ordonnés).
      let tick = 0;
      videos = new InMemoryVideoRepository(() => new Date(Date.UTC(2026, 0, 1) + ++tick * 1000));
      service = new VideosService(videos, storage, queue, events, cleanup, new InMemoryRateLimiter());
      const ids = [await transcoded('#chat'), await transcoded('#chien'), await transcoded('#chat'), await transcoded('#Chat')];
      const first = await service.listHashtagVideos('#chat', null, 2);
      expect(first.map((p) => p.videoId)).toEqual([ids[3], ids[2]]);
      const rest = await service.listHashtagVideos('chat', first[1], 2);
      expect(rest.map((p) => p.videoId)).toEqual([ids[0]]);
      await expect(service.listHashtagVideos('a b', null, 2)).rejects.toBeInstanceOf(InvalidHashtagError);
    });

    it('tendances : vidéos publiées ces 7 derniers jours, puis nombre total', async () => {
      let clock = new Date('2026-01-01T00:00:00Z');
      videos = new InMemoryVideoRepository(() => clock);
      service = new VideosService(videos, storage, queue, events, cleanup, new InMemoryRateLimiter(), () => clock);
      await transcoded('#ancien #ancien2');
      await transcoded('#ancien');
      await transcoded('#ancien2');
      clock = new Date('2026-01-20T00:00:00Z');
      await transcoded('#nouveau');

      await expect(service.trendingHashtags()).resolves.toEqual([
        { name: 'nouveau', videosCount: 1 },
        { name: 'ancien', videosCount: 2 },
        { name: 'ancien2', videosCount: 2 },
      ]);
    });
  });

  describe('vidéos privées (ADR-061)', () => {
    async function published(visibility: 'public' | 'private', description = '#été') {
      const { video } = await service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: 1000, description, visibility });
      await service.completeUpload(ALICE, video.id, uploadAllParts(video.uploadId!, 1000, 1));
      await service.applyTranscodeResult(video.id, { status: 'ready', hlsUrl: 'a', thumbnailUrl: 'b' });
      return video.id;
    }

    it('une vidéo privée n’est rendue qu’à son auteur, et n’est rangée sous aucun hashtag', async () => {
      const hidden = await published('private');
      const shown = await published('public');
      expect((await service.getVideo(hidden, ALICE)).visibility).toBe('private');
      expect((await service.getPublishedVideos([hidden, shown], null)).map((v) => v.id)).toEqual([shown]);
      expect((await service.getPublishedVideos([hidden, shown], BOB)).map((v) => v.id)).toEqual([shown]);
      expect((await service.getPublishedVideos([hidden, shown], ALICE)).map((v) => v.id)).toEqual([hidden, shown]);
      expect(await service.getPublishedVideosIncludingPrivate([hidden])).toHaveLength(1);
      await expect(service.getHashtag('été')).resolves.toEqual({ name: 'été', videosCount: 1 });
      expect((await service.listPublishedByAuthor(ALICE, null, 10)).map((v) => v.id)).toEqual([shown]);
      expect((await service.listPublishedByAuthor(ALICE, null, 10, 'private')).map((v) => v.id)).toEqual([hidden]);
      expect(await service.listPublishedVideoIds(10)).toEqual([shown]);
    });

    it('par son auteur seulement ; les hashtags suivent ; le compteur de likes reçus ne compte que les publiques', async () => {
      const id = await published('public');
      videos.adjustCounter(id, 'likesCount', 3);
      await expect(service.countLikesReceived(ALICE)).resolves.toBe(3);
      await expect(service.setVisibility(BOB, id, 'private')).rejects.toBeInstanceOf(VideoNotFoundError);

      await expect(service.setVisibility(ALICE, id, 'private')).resolves.toMatchObject({ visibility: 'private' });
      await expect(service.getHashtag('été')).resolves.toEqual({ name: 'été', videosCount: 0 });
      await expect(service.countLikesReceived(ALICE)).resolves.toBe(0);

      await expect(service.setVisibility(ALICE, id, 'public')).resolves.toMatchObject({ visibility: 'public' });
      await expect(service.getHashtag('été')).resolves.toEqual({ name: 'été', videosCount: 1 });
      await expect(service.countLikesReceived(ALICE)).resolves.toBe(3);
    });
  });

  describe('commentaires désactivables (ADR-062)', () => {
    it('autorisés par défaut, choisis à l’envoi, changés par l’auteur seulement', async () => {
      const { video } = await service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: 1000 });
      expect((await service.getVideo(video.id, ALICE)).commentsEnabled).toBe(true);
      const { video: closed } = await service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: 1000, commentsEnabled: false });
      expect((await service.getVideo(closed.id, ALICE)).commentsEnabled).toBe(false);

      await expect(service.setCommentsEnabled(BOB, video.id, false)).rejects.toBeInstanceOf(VideoNotFoundError);
      await expect(service.setCommentsEnabled(ALICE, video.id, false)).resolves.toMatchObject({ commentsEnabled: false });
      await expect(service.setCommentsEnabled(ALICE, video.id, true)).resolves.toMatchObject({ commentsEnabled: true });
    });
  });

  describe('maintenance', () => {
    let now: Date;

    beforeEach(() => {
      now = new Date('2026-01-01T00:00:00Z');
      videos = new InMemoryVideoRepository(() => now);
      service = new VideosService(videos, storage, queue, events, cleanup, new InMemoryRateLimiter(), () => now);
    });

    it('supprime les uploads non confirmés depuis plus de 24 h et annule leur multipart', async () => {
      const { video: old } = await service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: 1000 });
      now = new Date('2026-01-01T20:00:00Z');
      const { video: recent } = await service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: 1000 });
      now = new Date('2026-01-02T01:00:00Z');

      await expect(service.purgeAbandonedUploads()).resolves.toBe(1);
      expect(videos.videos.has(old.id)).toBe(false);
      expect(storage.uploads.has(old.uploadId!)).toBe(false);
      expect(videos.videos.has(recent.id)).toBe(true);
    });

    it('remet dans la file les vidéos bloquées en processing depuis plus d’1 h', async () => {
      const { video } = await service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: 1000 });
      await service.completeUpload(ALICE, video.id, uploadAllParts(video.uploadId!, 1000, 1));
      expect(queue.jobs).toHaveLength(1);

      now = new Date('2026-01-01T00:30:00Z');
      await expect(service.requeueStuckTranscodes()).resolves.toBe(0);

      now = new Date('2026-01-01T01:01:00Z');
      await expect(service.requeueStuckTranscodes()).resolves.toBe(1);
      expect(queue.jobs).toEqual([
        { videoId: video.id, rawKey: video.rawKey },
        { videoId: video.id, rawKey: video.rawKey },
      ]);
    });
  });

  describe('deleteVideo', () => {
    async function videoWithStatus(status: 'uploading' | 'processing' | 'ready' | 'failed') {
      const { video } = await service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: 1000 });
      Object.assign(videos.videos.get(video.id)!, { status });
      return video;
    }

    it('supprime la vidéo de son auteur et programme le nettoyage de ses fichiers, avec délai', async () => {
      const video = await videoWithStatus('ready');
      await service.deleteVideo(ALICE, video.id);
      expect(videos.videos.has(video.id)).toBe(false);
      expect(cleanup.scheduled).toEqual([
        { cleanup: { videoId: video.id, rawKey: video.rawKey, uploadId: video.uploadId }, delayMs: CLEANUP_DELAY_MS },
      ]);
      expect(queue.cancelled).toEqual([]);
      await expect(service.deleteVideo(ALICE, video.id)).rejects.toBeInstanceOf(VideoNotFoundError);
    });

    it("retire le job de transcodage d'une vidéo en traitement", async () => {
      const video = await videoWithStatus('processing');
      await service.deleteVideo(ALICE, video.id);
      expect(queue.cancelled).toEqual([video.id]);
    });

    it("refuse la vidéo d'un autre compte ou inconnue, sans rien supprimer", async () => {
      const video = await videoWithStatus('ready');
      await expect(service.deleteVideo(BOB, video.id)).rejects.toBeInstanceOf(VideoNotFoundError);
      await expect(service.deleteVideo(ALICE, 'inconnue')).rejects.toBeInstanceOf(VideoNotFoundError);
      expect(videos.videos.has(video.id)).toBe(true);
      expect(cleanup.scheduled).toEqual([]);
    });

    it('prévient les écouteurs avant la suppression en base, par son auteur ou un administrateur ; un échec la fait échouer', async () => {
      const seen: [string, boolean][] = [];
      service.onVideoRemoving(async (videoId) => {
        seen.push([videoId, videos.videos.has(videoId)]);
      });
      const first = await videoWithStatus('ready');
      const second = await videoWithStatus('failed');
      await service.deleteVideo(ALICE, first.id);
      await service.removeVideo(second.id);
      expect(seen).toEqual([
        [first.id, true],
        [second.id, true],
      ]);

      const third = await videoWithStatus('ready');
      service.onVideoRemoving(async () => {
        throw new Error('base indisponible');
      });
      await expect(service.deleteVideo(ALICE, third.id)).rejects.toThrow('base indisponible');
      expect(videos.videos.has(third.id)).toBe(true);
    });

    it('ne supprime pas la vidéo si le nettoyage ne peut pas être programmé', async () => {
      const video = await videoWithStatus('ready');
      cleanup.schedule = async () => {
        throw new Error('Redis indisponible');
      };
      await expect(service.deleteVideo(ALICE, video.id)).rejects.toThrow('Redis indisponible');
      expect(videos.videos.has(video.id)).toBe(true);
    });

    it('le nettoyage supprime le brut, annule le multipart et supprime les fichiers HLS', async () => {
      const video = await videoWithStatus('uploading');
      storage.objects.set(video.rawKey, 1000);
      storage.hlsFiles.set(video.id, [`${video.id}/master.m3u8`]);

      // Vidéo encore en base (suppression échouée ou pas encore faite) : rien n'est touché.
      const files = { videoId: video.id, rawKey: video.rawKey, uploadId: video.uploadId };
      await expect(service.cleanupFiles(files)).resolves.toBe(false);
      expect(storage.objects.has(video.rawKey)).toBe(true);

      await service.deleteVideo(ALICE, video.id);
      await expect(service.cleanupFiles(files)).resolves.toBe(true);
      expect(storage.objects.has(video.rawKey)).toBe(false);
      expect(storage.uploads.has(video.uploadId!)).toBe(false);
      expect(storage.hlsFiles.has(video.id)).toBe(false);
      // Idempotent.
      await expect(service.cleanupFiles(files)).resolves.toBe(true);
    });

    it("programme le nettoyage de toutes les vidéos d'un compte supprimé", async () => {
      const ready = await videoWithStatus('ready');
      const processing = await videoWithStatus('processing');
      const { video: bobVideo } = await service.createUpload(BOB, { contentType: 'video/mp4', fileSize: 1000 });

      await expect(service.scheduleAuthorFilesCleanup(ALICE)).resolves.toBe(2);
      expect(cleanup.scheduled.map((s) => s.cleanup.videoId).sort()).toEqual([ready.id, processing.id].sort());
      expect(cleanup.scheduled.every((s) => s.delayMs === CLEANUP_DELAY_MS)).toBe(true);
      expect(queue.cancelled).toEqual([processing.id]);
      expect(cleanup.scheduled.some((s) => s.cleanup.videoId === bobVideo.id)).toBe(false);
      await expect(service.scheduleAuthorFilesCleanup('sans-video')).resolves.toBe(0);
    });
  });

  describe('listUnpublishedVideos', () => {
    it("ne donne à l'auteur que ses vidéos en traitement ou en échec, de la plus récente à la plus ancienne", async () => {
      const at = (iso: string) => new Date(iso);
      const create = async (userId: string, status: 'uploading' | 'processing' | 'ready' | 'failed', createdAt: Date) => {
        const video = await videos.create({ userId, description: null, rawKey: 'k', uploadId: 'u', rawSize: 1 });
        Object.assign(videos.videos.get(video.id)!, { status, createdAt });
        return video.id;
      };
      const failed = await create(ALICE, 'failed', at('2026-01-01T00:00:00Z'));
      const processing = await create(ALICE, 'processing', at('2026-01-02T00:00:00Z'));
      await create(ALICE, 'uploading', at('2026-01-03T00:00:00Z'));
      await create(ALICE, 'ready', at('2026-01-04T00:00:00Z'));
      await create(BOB, 'processing', at('2026-01-05T00:00:00Z'));

      const pending = await service.listUnpublishedVideos(ALICE);
      expect(pending.map((v) => [v.id, v.status])).toEqual([
        [processing, 'processing'],
        [failed, 'failed'],
      ]);
    });
  });

  describe('getVideo', () => {
    it("ne montre une vidéo pas encore prête qu'à son auteur", async () => {
      const { video } = await service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: 1000 });

      await expect(service.getVideo(video.id, ALICE)).resolves.toMatchObject({ id: video.id });
      await expect(service.getVideo(video.id, BOB)).rejects.toBeInstanceOf(VideoNotFoundError);
      await expect(service.getVideo(video.id, null)).rejects.toBeInstanceOf(VideoNotFoundError);
    });

    it('montre une vidéo prête à tout le monde, invités compris', async () => {
      const { video } = await service.createUpload(ALICE, { contentType: 'video/mp4', fileSize: 1000 });
      videos.videos.get(video.id)!.status = 'ready';

      await expect(service.getVideo(video.id, null)).resolves.toMatchObject({ status: 'ready' });
    });
  });

  describe('backoffice (ADR-004)', () => {
    async function videoOf(userId: string, status: 'uploading' | 'processing' | 'ready' | 'failed') {
      const { video } = await service.createUpload(userId, { contentType: 'video/mp4', fileSize: 1000 });
      Object.assign(videos.videos.get(video.id)!, { status });
      return video;
    }

    it("likes reçus d'un compte (ADR-056) : somme des likes de ses vidéos publiées seulement", async () => {
      const first = await videoOf(ALICE, 'ready');
      const second = await videoOf(ALICE, 'ready');
      const failed = await videoOf(ALICE, 'failed');
      const other = await videoOf(BOB, 'ready');
      videos.adjustCounter(first.id, 'likesCount', 3);
      videos.adjustCounter(second.id, 'likesCount', 2);
      videos.adjustCounter(failed.id, 'likesCount', 7);
      videos.adjustCounter(other.id, 'likesCount', 5);
      expect(await service.countLikesReceived(ALICE)).toBe(5);
      expect(await service.countLikesReceived('sans-video')).toBe(0);
    });

    it("retire la vidéo de n'importe quel auteur, avec le même nettoyage que l'auteur", async () => {
      const video = await videoOf(BOB, 'processing');
      await service.removeVideo(video.id);
      expect(videos.videos.has(video.id)).toBe(false);
      expect(cleanup.scheduled).toEqual([
        { cleanup: { videoId: video.id, rawKey: video.rawKey, uploadId: video.uploadId }, delayMs: CLEANUP_DELAY_MS },
      ]);
      expect(queue.cancelled).toEqual([video.id]);
      await expect(service.removeVideo(video.id)).rejects.toBeInstanceOf(VideoNotFoundError);
    });

    it('liste toutes les vidéos, filtrées par statut et par auteur, de la plus récente à la plus ancienne', async () => {
      const ready = await videoOf(ALICE, 'ready');
      const failed = await videoOf(ALICE, 'failed');
      const other = await videoOf(BOB, 'ready');
      const all = [ready, failed, other]
        .map((v) => v.id)
        .sort()
        .reverse();

      expect((await service.listVideoDetails({}, null, 10)).map((v) => v.id)).toEqual(all);
      expect((await service.listVideoDetails({}, all[0], 10)).map((v) => v.id)).toEqual(all.slice(1));
      expect((await service.listVideoDetails({ status: 'ready' }, null, 10)).map((v) => v.id).sort()).toEqual([ready.id, other.id].sort());
      expect(await service.listVideoDetails({ status: 'ready', userId: ALICE }, null, 10)).toMatchObject([
        { id: ready.id, status: 'ready', likesCount: 0 },
      ]);
      expect(await service.getVideoDetails([failed.id, 'inconnue', failed.id])).toMatchObject([{ id: failed.id, status: 'failed' }]);
    });

    it('compte les vidéos par statut et par auteur', async () => {
      await videoOf(ALICE, 'ready');
      await videoOf(ALICE, 'failed');
      await videoOf(BOB, 'ready');
      await expect(service.countVideos(new Date('2025-12-31T00:00:00Z'))).resolves.toEqual({
        byStatus: { uploading: 0, processing: 0, ready: 2, failed: 1 },
        createdSince: 3,
      });
      await expect(service.countVideos(new Date(Date.now() + 60_000))).resolves.toMatchObject({ createdSince: 0 });
      await expect(service.countVideosByAuthors([ALICE, BOB, 'personne'])).resolves.toEqual(
        new Map([
          [ALICE, 2],
          [BOB, 1],
        ]),
      );
    });
  });
});
