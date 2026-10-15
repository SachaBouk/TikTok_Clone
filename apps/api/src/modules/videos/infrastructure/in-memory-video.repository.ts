import { randomUUID } from 'node:crypto';
import type { Hashtag, HashtagVideoPosition } from '../domain/hashtags';
import type { NewVideo, PublishedVideo, TranscodeOutcome, Video, VideoDetails, VideoFilter, VideoPosition, VideoStatus } from '../domain/video';
import { VideoRepository } from '../domain/video.repository';

type Counter = 'viewsCount' | 'likesCount' | 'commentsCount' | 'favoritesCount' | 'sharesCount' | 'repostsCount';
// `hashtags` : écrits au passage en `ready` (ADR-049), avec la date de publication.
type StoredVideo = Video & { updatedAt: Date; counters: Record<Counter, number>; hashtags?: { names: string[]; taggedAt: Date } };

// Adaptateur en mémoire pour les tests. `now` permet de dater les écritures (tests de maintenance).
export class InMemoryVideoRepository extends VideoRepository {
  readonly videos = new Map<string, StoredVideo>();

  constructor(private readonly now: () => Date = () => new Date()) {
    super();
  }

  async create(video: NewVideo): Promise<Video> {
    const created: StoredVideo = {
      ...video,
      id: randomUUID(),
      status: 'uploading',
      hlsUrl: null,
      thumbnailUrl: null,
      createdAt: this.now(),
      updatedAt: this.now(),
      counters: { viewsCount: 0, likesCount: 0, commentsCount: 0, favoritesCount: 0, sharesCount: 0, repostsCount: 0 },
    };
    this.videos.set(created.id, created);
    return toVideo(created);
  }

  async findById(id: string): Promise<Video | null> {
    const video = this.videos.get(id);
    return video ? toVideo(video) : null;
  }

  async markUploaded(id: string): Promise<Video | null> {
    const video = this.videos.get(id);
    if (!video || video.status !== 'uploading') return null;
    Object.assign(video, { status: 'processing', uploadId: null, updatedAt: this.now() });
    return toVideo(video);
  }

  async markFailed(id: string): Promise<void> {
    const video = this.videos.get(id);
    if (video) Object.assign(video, { status: 'failed', uploadId: null, updatedAt: this.now() });
  }

  async finishTranscoding(id: string, outcome: TranscodeOutcome, hashtags: string[]): Promise<boolean> {
    const video = this.videos.get(id);
    if (!video || video.status !== 'processing') return false;
    Object.assign(video, outcome, { updatedAt: this.now() });
    if (outcome.status === 'ready' && hashtags.length > 0) video.hashtags = { names: hashtags, taggedAt: this.now() };
    return true;
  }

  async findAbandonedUploads(createdBefore: Date, limit: number): Promise<Video[]> {
    return [...this.videos.values()]
      .filter((v) => v.status === 'uploading' && v.createdAt < createdBefore)
      .slice(0, limit)
      .map(toVideo);
  }

  async findStuckTranscodes(updatedBefore: Date, limit: number): Promise<Video[]> {
    return [...this.videos.values()]
      .filter((v) => v.status === 'processing' && v.updatedAt < updatedBefore)
      .slice(0, limit)
      .map(toVideo);
  }

  async delete(id: string): Promise<void> {
    this.videos.delete(id);
  }

  async findAllByAuthor(userId: string): Promise<Video[]> {
    return [...this.videos.values()].filter((v) => v.userId === userId).map(toVideo);
  }

  async listPublishedIds(limit: number): Promise<string[]> {
    return [...this.videos.values()]
      .filter((v) => v.status === 'ready')
      .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())
      .slice(0, limit)
      .map((v) => v.id);
  }

  async findPublishedByIds(ids: string[]): Promise<PublishedVideo[]> {
    return ids.flatMap((id) => {
      const video = this.videos.get(id);
      const published = video && toPublished(video);
      return published ? [published] : [];
    });
  }

  async findPublishedByAuthors(userIds: string[], after: VideoPosition | null, limit: number): Promise<PublishedVideo[]> {
    const authors = new Set(userIds);
    return [...this.videos.values()]
      .filter((v) => authors.has(v.userId))
      .sort(newestFirst)
      .filter((v) => !after || newestFirst(after, v) < 0)
      .flatMap((v) => toPublished(v) ?? [])
      .slice(0, limit);
  }

  async findUnpublishedByAuthor(userId: string, limit: number): Promise<Video[]> {
    return [...this.videos.values()]
      .filter((v) => v.userId === userId && (v.status === 'processing' || v.status === 'failed'))
      .sort(newestFirst)
      .slice(0, limit)
      .map(toVideo);
  }

  async incrementShares(id: string): Promise<number | null> {
    const video = this.videos.get(id);
    if (!video || video.status !== 'ready') return null;
    return ++video.counters.sharesCount;
  }

  async findDetails(filter: VideoFilter, beforeId: string | null, limit: number): Promise<VideoDetails[]> {
    return [...this.videos.values()]
      .filter((v) => (!filter.status || v.status === filter.status) && (!filter.userId || v.userId === filter.userId))
      .filter((v) => !beforeId || v.id < beforeId)
      .sort((a, b) => (a.id < b.id ? 1 : -1))
      .slice(0, limit)
      .map(toDetails);
  }

  async findDetailsByIds(ids: string[]): Promise<VideoDetails[]> {
    return ids.flatMap((id) => {
      const video = this.videos.get(id);
      return video ? [toDetails(video)] : [];
    });
  }

  async countByStatus(): Promise<Record<VideoStatus, number>> {
    const counts: Record<VideoStatus, number> = { uploading: 0, processing: 0, ready: 0, failed: 0 };
    for (const video of this.videos.values()) counts[video.status]++;
    return counts;
  }

  async countCreatedSince(since: Date): Promise<number> {
    return [...this.videos.values()].filter((v) => v.createdAt >= since).length;
  }

  async countByAuthors(userIds: string[]): Promise<Map<string, number>> {
    const counts = new Map<string, number>();
    for (const video of this.videos.values()) {
      if (userIds.includes(video.userId)) counts.set(video.userId, (counts.get(video.userId) ?? 0) + 1);
    }
    return counts;
  }

  async sumLikesByAuthor(userId: string): Promise<number> {
    let sum = 0;
    for (const video of this.videos.values()) {
      if (video.userId === userId && video.status === 'ready') sum += video.counters.likesCount;
    }
    return sum;
  }

  // Reproduit les triggers de compteurs de la base (migration interaction_counters), pour les tests.
  adjustCounter(id: string, counter: Counter, delta: number) {
    const video = this.videos.get(id);
    if (video) video.counters[counter] = Math.max(0, video.counters[counter] + delta);
  }

  async findHashtag(name: string): Promise<Hashtag | null> {
    const count = this.tagged().filter((v) => v.hashtags.names.includes(name)).length;
    return count > 0 ? { name, videosCount: count } : null;
  }

  async searchHashtags(prefix: string, limit: number): Promise<Hashtag[]> {
    return this.hashtagCounts(null)
      .filter((h) => h.name.startsWith(prefix))
      .sort((a, b) => b.videosCount - a.videosCount || compareNames(a.name, b.name))
      .slice(0, limit)
      .map(({ name, videosCount }) => ({ name, videosCount }));
  }

  async findTrendingHashtags(since: Date, limit: number): Promise<Hashtag[]> {
    return this.hashtagCounts(since)
      .sort((a, b) => b.recent - a.recent || b.videosCount - a.videosCount || compareNames(a.name, b.name))
      .slice(0, limit)
      .map(({ name, videosCount }) => ({ name, videosCount }));
  }

  async listHashtagVideos(name: string, after: HashtagVideoPosition | null, limit: number): Promise<HashtagVideoPosition[]> {
    const newest = (a: HashtagVideoPosition, b: HashtagVideoPosition) =>
      newestFirst({ createdAt: a.taggedAt, id: a.videoId }, { createdAt: b.taggedAt, id: b.videoId });
    return this.tagged()
      .filter((v) => v.hashtags.names.includes(name))
      .map((v) => ({ videoId: v.id, taggedAt: v.hashtags.taggedAt }))
      .sort(newest)
      .filter((position) => !after || newest(after, position) < 0)
      .slice(0, limit);
  }

  // Vidéos publiées avec des hashtags (la cascade de la base les retire avec la vidéo).
  private tagged() {
    return [...this.videos.values()].flatMap((v) => (v.status === 'ready' && v.hashtags ? [{ ...v, hashtags: v.hashtags }] : []));
  }

  // Nombre de vidéos par hashtag, et celles publiées depuis `since`.
  private hashtagCounts(since: Date | null) {
    const counts = new Map<string, { name: string; videosCount: number; recent: number }>();
    for (const video of this.tagged()) {
      for (const name of video.hashtags.names) {
        const entry = counts.get(name) ?? { name, videosCount: 0, recent: 0 };
        entry.videosCount++;
        if (since && video.hashtags.taggedAt >= since) entry.recent++;
        counts.set(name, entry);
      }
    }
    return [...counts.values()];
  }
}

// Ordre des noms pour les tests (comparaison simple, sans classement linguistique : suffisant ici).
function compareNames(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

function toVideo({ updatedAt: _updatedAt, counters: _counters, ...video }: StoredVideo): Video {
  return { ...video };
}

function toDetails(v: StoredVideo): VideoDetails {
  return {
    id: v.id,
    userId: v.userId,
    description: v.description,
    status: v.status,
    hlsUrl: v.hlsUrl,
    thumbnailUrl: v.thumbnailUrl,
    ...v.counters,
    createdAt: v.createdAt,
  };
}

function toPublished(v: StoredVideo): PublishedVideo | null {
  if (v.status !== 'ready' || !v.hlsUrl || !v.thumbnailUrl) return null;
  return {
    id: v.id,
    userId: v.userId,
    description: v.description,
    hlsUrl: v.hlsUrl,
    thumbnailUrl: v.thumbnailUrl,
    ...v.counters,
    createdAt: v.createdAt,
  };
}

// De la plus récente à la plus ancienne, puis par identifiant décroissant (même ordre que la base).
function newestFirst(a: VideoPosition, b: VideoPosition): number {
  const byDate = b.createdAt.getTime() - a.createdAt.getTime();
  if (byDate !== 0) return byDate;
  return a.id < b.id ? 1 : a.id > b.id ? -1 : 0;
}
