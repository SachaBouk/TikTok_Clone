import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../../database/prisma.service';
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
  async finishTranscoding(id: string, outcome: TranscodeOutcome): Promise<boolean> {
    const data =
      outcome.status === 'ready'
        ? { status: 'ready' as const, hlsUrl: outcome.hlsUrl, thumbnailUrl: outcome.thumbnailUrl }
        : { status: 'failed' as const };
    const { count } = await this.prisma.video.updateMany({ where: { id, status: 'processing' }, data });
    return count === 1;
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
  async findPublishedByAuthor(userId: string, after: VideoPosition | null, limit: number): Promise<PublishedVideo[]> {
    const rows = await this.prisma.video.findMany({
      where: {
        userId,
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
function toPublished({ hlsUrl, thumbnailUrl, ...video }: { hlsUrl: string | null; thumbnailUrl: string | null } & Omit<PublishedVideo, 'hlsUrl' | 'thumbnailUrl'>): PublishedVideo[] {
  return hlsUrl && thumbnailUrl ? [{ ...video, hlsUrl, thumbnailUrl }] : [];
}
