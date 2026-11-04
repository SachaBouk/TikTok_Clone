import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../../database/prisma.service';
import type { Prisma } from '../../../generated/prisma/client';
import { type Collection, COLLECTION_COVER_CANDIDATES, type CollectionVideoRow, type CollectionVisibility } from '../domain/collection';
import { CollectionRepository } from '../domain/collection.repository';

// Champs du type de domaine seulement, avec le nombre de vidéos et les plus récentes (image).
const collectionSelect = {
  id: true,
  userId: true,
  name: true,
  visibility: true,
  createdAt: true,
  updatedAt: true,
  _count: { select: { videos: true } },
  videos: { orderBy: [{ createdAt: 'desc' }, { videoId: 'desc' }], take: COLLECTION_COVER_CANDIDATES, select: { videoId: true } },
} satisfies Prisma.CollectionSelect;

type CollectionRow = Prisma.CollectionGetPayload<{ select: typeof collectionSelect }>;

@Injectable()
export class PrismaCollectionRepository extends CollectionRepository {
  constructor(private readonly prisma: PrismaService) {
    super();
  }

  async create(userId: string, name: string, visibility: CollectionVisibility): Promise<Collection> {
    return toCollection(await this.prisma.collection.create({ data: { userId, name, visibility }, select: collectionSelect }));
  }

  async findById(id: string): Promise<Collection | null> {
    // Comparer une colonne uuid à autre chose qu'un UUID ferait échouer la requête.
    if (!UUID_PATTERN.test(id)) return null;
    const row = await this.prisma.collection.findUnique({ where: { id }, select: collectionSelect });
    return row && toCollection(row);
  }

  async findByIds(ids: string[]): Promise<Collection[]> {
    const valid = ids.filter((id) => UUID_PATTERN.test(id));
    if (valid.length === 0) return [];
    return (await this.prisma.collection.findMany({ where: { id: { in: valid } }, select: collectionSelect })).map(toCollection);
  }

  async listByOwner(userId: string, onlyPublic: boolean): Promise<Collection[]> {
    const rows = await this.prisma.collection.findMany({
      where: { userId, ...(onlyPublic ? { visibility: 'public' as const } : {}) },
      orderBy: [{ updatedAt: 'desc' }, { id: 'desc' }],
      select: collectionSelect,
    });
    return rows.map(toCollection);
  }

  countByOwner(userId: string): Promise<number> {
    return this.prisma.collection.count({ where: { userId } });
  }

  async update(id: string, changes: { name?: string; visibility?: CollectionVisibility }): Promise<Collection | null> {
    const { count } = await this.prisma.collection.updateMany({ where: { id }, data: changes });
    return count === 1 ? this.findById(id) : null;
  }

  async delete(id: string): Promise<boolean> {
    const { count } = await this.prisma.collection.deleteMany({ where: { id } });
    return count === 1;
  }

  async addVideos(id: string, userId: string, videoIds: string[]): Promise<void> {
    await this.prisma.$transaction([
      this.prisma.collectionVideo.createMany({ data: videoIds.map((videoId) => ({ collectionId: id, userId, videoId })), skipDuplicates: true }),
      this.prisma.collection.updateMany({ where: { id }, data: { updatedAt: new Date() } }),
    ]);
  }

  async removeVideos(id: string, videoIds: string[]): Promise<void> {
    await this.prisma.collectionVideo.deleteMany({ where: { collectionId: id, videoId: { in: videoIds } } });
  }

  async listVideos(id: string, after: CollectionVideoRow | null, limit: number): Promise<CollectionVideoRow[]> {
    const rows = await this.prisma.collectionVideo.findMany({
      where: {
        collectionId: id,
        ...(after && {
          OR: [{ createdAt: { lt: after.addedAt } }, { createdAt: after.addedAt, videoId: { lt: after.videoId } }],
        }),
      },
      orderBy: [{ createdAt: 'desc' }, { videoId: 'desc' }],
      take: limit,
      select: { videoId: true, createdAt: true },
    });
    return rows.map((row) => ({ videoId: row.videoId, addedAt: row.createdAt }));
  }

  async findContaining(userId: string, videoId: string): Promise<Set<string>> {
    const rows = await this.prisma.collectionVideo.findMany({ where: { userId, videoId }, select: { collectionId: true } });
    return new Set(rows.map((row) => row.collectionId));
  }
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function toCollection(row: CollectionRow): Collection {
  return {
    id: row.id,
    userId: row.userId,
    name: row.name,
    visibility: row.visibility,
    videosCount: row._count.videos,
    recentVideoIds: row.videos.map((v) => v.videoId),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  };
}
