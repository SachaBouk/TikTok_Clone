import { randomUUID } from 'node:crypto';
import type { NewVideo, PublishedVideo, TranscodeOutcome, Video, VideoDetails, VideoFilter, VideoPosition, VideoStatus } from '../domain/video';
import { VideoRepository } from '../domain/video.repository';

type Counter = 'viewsCount' | 'likesCount' | 'commentsCount' | 'favoritesCount' | 'sharesCount' | 'repostsCount';
type StoredVideo = Video & { updatedAt: Date; counters: Record<Counter, number> };

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

  async finishTranscoding(id: string, outcome: TranscodeOutcome): Promise<boolean> {
    const video = this.videos.get(id);
    if (!video || video.status !== 'processing') return false;
    Object.assign(video, outcome, { updatedAt: this.now() });
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

  async findPublishedByAuthor(userId: string, after: VideoPosition | null, limit: number): Promise<PublishedVideo[]> {
    return [...this.videos.values()]
      .filter((v) => v.userId === userId)
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

  // Reproduit les triggers de compteurs de la base (migration interaction_counters), pour les tests.
  adjustCounter(id: string, counter: Counter, delta: number) {
    const video = this.videos.get(id);
    if (video) video.counters[counter] = Math.max(0, video.counters[counter] + delta);
  }
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
