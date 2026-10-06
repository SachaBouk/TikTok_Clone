import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../../database/prisma.service';
import type { Hashtag, HashtagVideoPosition } from '../domain/hashtags';
import type { NewVideo, PublishedVideo, TranscodeOutcome, Video, VideoDetails, VideoFilter, VideoPosition, VideoStatus } from '../domain/video';
import { VideoRepository } from '../domain/video.repository';

const videoSelect = {
  id: true,
  userId: true,
  description: true,
  rawKey: true,
  uploadId: true,
  rawSize: true,
  status: true,
  hlsUrl: true,
  thumbnailUrl: true,
  createdAt: true,
} as const;

@Injectable()
export class PrismaVideoRepository extends VideoRepository {
  constructor(private readonly prisma: PrismaService) {
    super();
  }

  create(video: NewVideo): Promise<Video> {
    return this.prisma.video.create({ data: video, select: videoSelect });
  }

  findById(id: string): Promise<Video | null> {
    return this.prisma.video.findUnique({ where: { id }, select: videoSelect });
  }

  // `status: 'uploading'` dans le WHERE rend la transition atomique : une seule confirmation l'emporte.
  async markUploaded(id: string): Promise<Video | null> {
    const [video] = await this.prisma.video.updateManyAndReturn({
      where: { id, status: 'uploading' },
      data: { status: 'processing', uploadId: null },
      select: videoSelect,
    });
    return video ?? null;
  }

  async markFailed(id: string): Promise<void> {
    await this.prisma.video.update({ where: { id }, data: { status: 'failed', uploadId: null } });
  }

  // `status: 'processing'` dans le WHERE : un résultat en double ou tardif n'écrase rien.
  async finishTranscoding(id: string, outcome: TranscodeOutcome, hashtags: string[]): Promise<boolean> {
    const data =
      outcome.status === 'ready'
        ? { status: 'ready' as const, hlsUrl: outcome.hlsUrl, thumbnailUrl: outcome.thumbnailUrl }
        : { status: 'failed' as const };
    return this.prisma.$transaction(async (tx) => {
      const { count } = await tx.video.updateMany({ where: { id, status: 'processing' }, data });
      if (count !== 1) return false;
      if (outcome.status === 'ready' && hashtags.length > 0) {
        // ON CONFLICT DO NOTHING : un hashtag créé en même temps par une autre publication est relu ensuite.
        await tx.hashtag.createMany({ data: hashtags.map((name) => ({ name })), skipDuplicates: true });
        const rows = await tx.hashtag.findMany({ where: { name: { in: hashtags } }, select: { id: true } });
        // `videos_count` suit par trigger (migration search_hashtags).
        await tx.videoHashtag.createMany({ data: rows.map((row) => ({ videoId: id, hashtagId: row.id })), skipDuplicates: true });
      }
      return true;
    });
  }

  findAbandonedUploads(createdBefore: Date, limit: number): Promise<Video[]> {
    return this.prisma.video.findMany({
      where: { status: 'uploading', createdAt: { lt: createdBefore } },
      orderBy: { createdAt: 'asc' },
      take: limit,
      select: videoSelect,
    });
  }

  findStuckTranscodes(updatedBefore: Date, limit: number): Promise<Video[]> {
    return this.prisma.video.findMany({
      where: { status: 'processing', updatedAt: { lt: updatedBefore } },
      orderBy: { updatedAt: 'asc' },
      take: limit,
      select: videoSelect,
    });
  }

  async delete(id: string): Promise<void> {
    await this.prisma.video.deleteMany({ where: { id } });
  }

  async listPublishedIds(limit: number): Promise<string[]> {
    const rows = await this.prisma.video.findMany({
      where: { status: 'ready' },
      orderBy: { createdAt: 'desc' },
      take: limit,
      select: { id: true },
    });
    return rows.map((row) => row.id);
  }

  async incrementShares(id: string): Promise<number | null> {
    const [video] = await this.prisma.video.updateManyAndReturn({
      where: { id, status: 'ready' },
      data: { sharesCount: { increment: 1 } },
      select: { sharesCount: true },
    });
    return video?.sharesCount ?? null;
  }

  findAllByAuthor(userId: string): Promise<Video[]> {
    return this.prisma.video.findMany({ where: { userId }, select: videoSelect });
  }

  async findPublishedByIds(ids: string[]): Promise<PublishedVideo[]> {
    if (ids.length === 0) return [];
    const rows = await this.prisma.video.findMany({ where: { id: { in: ids }, status: 'ready' }, select: publishedSelect });
    return rows.flatMap(toPublished);
  }

  // Pagination par clé (created_at, video_id), sur l'index (user_id, created_at).
  // Index `videos(user_id, created_at)`.
  async findPublishedByAuthors(userIds: string[], after: VideoPosition | null, limit: number): Promise<PublishedVideo[]> {
    if (userIds.length === 0) return [];
    const rows = await this.prisma.video.findMany({
      where: {
        userId: { in: userIds },
        status: 'ready',
        ...(after ? { OR: [{ createdAt: { lt: after.createdAt } }, { createdAt: after.createdAt, id: { lt: after.id } }] } : {}),
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit,
      select: publishedSelect,
    });
    return rows.flatMap(toPublished);
  }

  findUnpublishedByAuthor(userId: string, limit: number): Promise<Video[]> {
    return this.prisma.video.findMany({
      where: { userId, status: { in: ['processing', 'failed'] } },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit,
      select: videoSelect,
    });
  }

  findDetails(filter: VideoFilter, beforeId: string | null, limit: number): Promise<VideoDetails[]> {
    return this.prisma.video.findMany({
      where: { status: filter.status, userId: filter.userId, id: beforeId ? { lt: beforeId } : undefined },
      orderBy: { id: 'desc' },
      take: limit,
      select: detailsSelect,
    });
  }

  findDetailsByIds(ids: string[]): Promise<VideoDetails[]> {
    if (ids.length === 0) return Promise.resolve([]);
    return this.prisma.video.findMany({ where: { id: { in: ids } }, select: detailsSelect });
  }

  async countByStatus(): Promise<Record<VideoStatus, number>> {
    const counts: Record<VideoStatus, number> = { uploading: 0, processing: 0, ready: 0, failed: 0 };
    const rows = await this.prisma.video.groupBy({ by: ['status'], _count: { _all: true } });
    for (const row of rows) counts[row.status] = row._count._all;
    return counts;
  }

  countCreatedSince(since: Date): Promise<number> {
    return this.prisma.video.count({ where: { createdAt: { gte: since } } });
  }

  findHashtag(name: string): Promise<Hashtag | null> {
    return this.prisma.hashtag.findUnique({ where: { name }, select: { name: true, videosCount: true } });
  }

  // `LIKE` sur l'index trigrammes ; « _ » est un joker de LIKE : échappé.
  searchHashtags(prefix: string, limit: number): Promise<Hashtag[]> {
    const pattern = `${prefix.replace(/[\\%_]/g, '\\$&')}%`;
    return this.prisma.$queryRaw<Hashtag[]>`
      SELECT name, videos_count AS "videosCount" FROM hashtags
      WHERE name LIKE ${pattern} AND videos_count > 0
      ORDER BY videos_count DESC, name
      LIMIT ${limit}`;
  }

  findTrendingHashtags(since: Date, limit: number): Promise<Hashtag[]> {
    return this.prisma.$queryRaw<Hashtag[]>`
      SELECT h.name, h.videos_count AS "videosCount"
      FROM hashtags h
      LEFT JOIN (
        SELECT hashtag_id, count(*) AS recent FROM video_hashtags WHERE created_at >= ${since} GROUP BY hashtag_id
      ) r ON r.hashtag_id = h.hashtag_id
      WHERE h.videos_count > 0
      ORDER BY coalesce(r.recent, 0) DESC, h.videos_count DESC, h.name
      LIMIT ${limit}`;
  }

  // Pagination par clé (created_at, video_id), sur l'index (hashtag_id, created_at).
  async listHashtagVideos(name: string, after: HashtagVideoPosition | null, limit: number): Promise<HashtagVideoPosition[]> {
    const rows = await this.prisma.videoHashtag.findMany({
      where: {
        hashtag: { name },
        ...(after ? { OR: [{ createdAt: { lt: after.taggedAt } }, { createdAt: after.taggedAt, videoId: { lt: after.videoId } }] } : {}),
      },
      orderBy: [{ createdAt: 'desc' }, { videoId: 'desc' }],
      take: limit,
      select: { videoId: true, createdAt: true },
    });
    return rows.map((row) => ({ videoId: row.videoId, taggedAt: row.createdAt }));
  }

  async countByAuthors(userIds: string[]): Promise<Map<string, number>> {
    if (userIds.length === 0) return new Map();
    const rows = await this.prisma.video.groupBy({ by: ['userId'], where: { userId: { in: userIds } }, _count: { _all: true } });
    return new Map(rows.map((row) => [row.userId, row._count._all]));
  }
}

const detailsSelect = {
  id: true,
  userId: true,
  description: true,
  status: true,
  hlsUrl: true,
  thumbnailUrl: true,
  viewsCount: true,
  likesCount: true,
  commentsCount: true,
  favoritesCount: true,
  sharesCount: true,
  repostsCount: true,
  createdAt: true,
} as const;

const publishedSelect = {
  id: true,
  userId: true,
  description: true,
  hlsUrl: true,
  thumbnailUrl: true,
  viewsCount: true,
  likesCount: true,
  commentsCount: true,
  favoritesCount: true,
  sharesCount: true,
  repostsCount: true,
  createdAt: true,
} as const;

// `ready` garantit les URLs, que le schéma déclare facultatives (nulles avant le transcodage).
function toPublished({
  hlsUrl,
  thumbnailUrl,
  ...video
}: { hlsUrl: string | null; thumbnailUrl: string | null } & Omit<PublishedVideo, 'hlsUrl' | 'thumbnailUrl'>): PublishedVideo[] {
  return hlsUrl && thumbnailUrl ? [{ ...video, hlsUrl, thumbnailUrl }] : [];
}
