import { Injectable } from '@nestjs/common';
import { Prisma } from '../../../generated/prisma/client';
import { PrismaService } from '../../../database/prisma.service';
import type { Hashtag, HashtagVideoPosition } from '../domain/hashtags';
import type {
  Sound,
  SoundQuery,
  NewVideo,
  PublishedVideo,
  TranscodeOutcome,
  Video,
  VideoDetails,
  VideoFilter,
  VideoPosition,
  VideoStatus,
  VideoVisibility,
} from '../domain/video';
import { VideoRepository } from '../domain/video.repository';

const videoSelect = {
  id: true,
  userId: true,
  description: true,
  rawKey: true,
  uploadId: true,
  rawSize: true,
  status: true,
  visibility: true,
  commentsEnabled: true,
  soundShared: true,
  soundId: true,
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
      const [updated] = await tx.video.updateManyAndReturn({
        where: { id, status: 'processing' },
        data,
        select: { visibility: true, userId: true },
      });
      if (!updated) return false;
      // Une vidéo privée n'est rangée sous aucun hashtag (ADR-061).
      if (outcome.status === 'ready' && updated.visibility === 'public') await tagVideo(tx, id, hashtags);
      // Son réutilisable (ADR-064), gardé même pour une vidéo privée : il est filtré à la lecture.
      if (outcome.status === 'ready' && outcome.sound) {
        await tx.sound.createMany({
          data: [{ videoId: id, userId: updated.userId, audioUrl: outcome.sound.audioUrl, durationMs: outcome.sound.durationMs }],
          skipDuplicates: true,
        });
      }
      return true;
    });
  }

  // Dans une transaction : la vidéo verrouillée par la mise à jour, deux changements simultanés se suivent.
  setVisibility(id: string, visibility: VideoVisibility, hashtags: string[]): Promise<Video | null> {
    return this.prisma.$transaction(async (tx) => {
      const [video] = await tx.video.updateManyAndReturn({ where: { id }, data: { visibility }, select: videoSelect });
      if (!video) return null;
      if (visibility === 'private') await tx.videoHashtag.deleteMany({ where: { videoId: id } });
      else if (video.status === 'ready') await tagVideo(tx, id, hashtags);
      return video;
    });
  }

  async setCommentsEnabled(id: string, enabled: boolean): Promise<Video | null> {
    const [video] = await this.prisma.video.updateManyAndReturn({ where: { id }, data: { commentsEnabled: enabled }, select: videoSelect });
    return video ?? null;
  }

  async setSoundShared(id: string, shared: boolean): Promise<Video | null> {
    const [video] = await this.prisma.video.updateManyAndReturn({ where: { id }, data: { soundShared: shared }, select: videoSelect });
    return video ?? null;
  }

  // Sons proposés (ADR-064) : vidéo d'origine publiée, publique, qui le permet, auteur non exclu. Le nombre de
  // publications compte les vidéos publiques publiées qui reprennent le son (index `videos(sound_id)`).
  findSounds(query: SoundQuery, excludedAuthorIds: string[], offset: number, limit: number): Promise<Sound[]> {
    const excluded = excludedAuthorIds.length > 0 ? excludedAuthorIds : ['00000000-0000-0000-0000-000000000000'];
    const select = Prisma.sql`
      SELECT s.sound_id AS id, s.video_id AS "videoId", s.user_id AS "userId", s.audio_url AS "audioUrl",
        s.duration_ms AS "durationMs", v.thumbnail_url AS "coverUrl", s.created_at AS "createdAt",
        (SELECT count(*)::int FROM videos u WHERE u.sound_id = s.sound_id AND u.status = 'ready' AND u.visibility = 'public') AS "usesCount"
      FROM sounds s JOIN videos v ON v.video_id = s.video_id`;
    const available = Prisma.sql`v.status = 'ready' AND v.visibility = 'public' AND v.sound_shared
      AND v.thumbnail_url IS NOT NULL AND NOT (s.user_id = ANY(${excluded}::uuid[]))`;
    switch (query.kind) {
      case 'recommended':
        return this.prisma.$queryRaw<Sound[]>`${select} WHERE ${available}
          ORDER BY "usesCount" DESC, s.created_at DESC, s.sound_id DESC OFFSET ${offset} LIMIT ${limit}`;
      case 'search': {
        // `ILIKE` : « % », « _ » et « \ » sont des jokers, échappés.
        const pattern = `%${query.text.replace(/[\\%_]/g, '\\$&')}%`;
        const authors = query.authorIds.length > 0 ? query.authorIds : ['00000000-0000-0000-0000-000000000000'];
        return this.prisma.$queryRaw<Sound[]>`${select} WHERE ${available}
          AND (v.description ILIKE ${pattern} OR s.user_id = ANY(${authors}::uuid[]))
          ORDER BY "usesCount" DESC, s.created_at DESC, s.sound_id DESC OFFSET ${offset} LIMIT ${limit}`;
      }
      case 'favorites':
        return this.prisma.$queryRaw<Sound[]>`${select} JOIN sound_favorites f ON f.sound_id = s.sound_id AND f.user_id = ${query.userId}::uuid
          WHERE ${available} ORDER BY f.created_at DESC, s.sound_id DESC OFFSET ${offset} LIMIT ${limit}`;
      case 'ids':
        return this.prisma.$queryRaw<Sound[]>`${select} WHERE ${available} AND s.sound_id = ANY(${query.ids}::uuid[])
          ORDER BY s.sound_id LIMIT ${limit}`;
    }
  }

  async setSoundFavorite(userId: string, soundId: string, active: boolean): Promise<boolean> {
    if (!active) {
      await this.prisma.soundFavorite.deleteMany({ where: { userId, soundId } });
      return true;
    }
    const exists = await this.prisma.sound.findUnique({ where: { id: soundId }, select: { id: true } });
    if (!exists) return false;
    await this.prisma.soundFavorite.createMany({ data: [{ userId, soundId }], skipDuplicates: true });
    return true;
  }

  async findFavoritedSoundIds(userId: string, soundIds: string[]): Promise<Set<string>> {
    const rows = await this.prisma.soundFavorite.findMany({ where: { userId, soundId: { in: soundIds } }, select: { soundId: true } });
    return new Set(rows.map((row) => row.soundId));
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
      where: { status: 'ready', visibility: 'public' },
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
  async findPublishedByAuthors(
    userIds: string[],
    after: VideoPosition | null,
    limit: number,
    visibility: VideoVisibility,
  ): Promise<PublishedVideo[]> {
    if (userIds.length === 0) return [];
    const rows = await this.prisma.video.findMany({
      where: {
        userId: { in: userIds },
        status: 'ready',
        visibility,
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

  async sumLikesByAuthor(userId: string): Promise<number> {
    const result = await this.prisma.video.aggregate({ where: { userId, status: 'ready', visibility: 'public' }, _sum: { likesCount: true } });
    return result._sum.likesCount ?? 0;
  }
}

const detailsSelect = {
  id: true,
  userId: true,
  description: true,
  status: true,
  visibility: true,
  commentsEnabled: true,
  soundShared: true,
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
  visibility: true,
  commentsEnabled: true,
  soundShared: true,
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

// Range une vidéo sous ses hashtags (ADR-049), dans la transaction `tx`.
async function tagVideo(tx: Prisma.TransactionClient, videoId: string, hashtags: string[]): Promise<void> {
  if (hashtags.length === 0) return;
  // ON CONFLICT DO NOTHING : un hashtag créé en même temps par une autre publication est relu ensuite.
  await tx.hashtag.createMany({ data: hashtags.map((name) => ({ name })), skipDuplicates: true });
  const rows = await tx.hashtag.findMany({ where: { name: { in: hashtags } }, select: { id: true } });
  // `videos_count` suit par trigger (migration search_hashtags).
  await tx.videoHashtag.createMany({ data: rows.map((row) => ({ videoId, hashtagId: row.id })), skipDuplicates: true });
}
