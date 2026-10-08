import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../../database/prisma.service';
import type { NewStory, Story, StoryAuthorSummary, StoryStats, StoryTranscodeOutcome, StoryView, StoryViewPosition } from '../domain/story';
import { StoryRepository } from '../domain/story.repository';

const storySelect = {
  id: true,
  userId: true,
  mediaType: true,
  status: true,
  rawKey: true,
  uploadId: true,
  rawSize: true,
  mediaUrl: true,
  thumbnailUrl: true,
  createdAt: true,
  publishedAt: true,
  expiresAt: true,
} as const;

// Une story visible : publiée et pas expirée.
const active = (now: Date) => ({ status: 'ready' as const, expiresAt: { gt: now } });

@Injectable()
export class PrismaStoryRepository extends StoryRepository {
  constructor(private readonly prisma: PrismaService) {
    super();
  }

  create(story: NewStory): Promise<Story> {
    return this.prisma.story.create({ data: story, select: storySelect });
  }

  findById(id: string): Promise<Story | null> {
    return this.prisma.story.findUnique({ where: { id }, select: storySelect });
  }

  countActiveOrPending(userId: string, now: Date): Promise<number> {
    return this.prisma.story.count({ where: { userId, OR: [{ status: { in: ['uploading', 'processing'] } }, active(now)] } });
  }

  // `status: 'uploading'` dans le WHERE rend la transition atomique : une seule confirmation l'emporte.
  async markUploaded(id: string): Promise<Story | null> {
    const [story] = await this.prisma.story.updateManyAndReturn({
      where: { id, status: 'uploading' },
      data: { status: 'processing', uploadId: null },
      select: storySelect,
    });
    return story ?? null;
  }

  async publishPhoto(id: string, mediaUrl: string, publishedAt: Date, expiresAt: Date): Promise<Story | null> {
    const [story] = await this.prisma.story.updateManyAndReturn({
      where: { id, status: 'uploading', mediaType: 'photo' },
      data: { status: 'ready', uploadId: null, mediaUrl, thumbnailUrl: mediaUrl, publishedAt, expiresAt },
      select: storySelect,
    });
    return story ?? null;
  }

  async markFailed(id: string): Promise<void> {
    await this.prisma.story.updateMany({ where: { id }, data: { status: 'failed', uploadId: null } });
  }

  // `status: 'processing'` dans le WHERE : un résultat en double ou tardif n'écrase rien.
  async finishTranscoding(id: string, outcome: StoryTranscodeOutcome, publishedAt: Date, expiresAt: Date): Promise<Story | null> {
    const data =
      outcome.status === 'ready'
        ? { status: 'ready' as const, mediaUrl: outcome.mediaUrl, thumbnailUrl: outcome.thumbnailUrl, publishedAt, expiresAt }
        : { status: 'failed' as const };
    const [story] = await this.prisma.story.updateManyAndReturn({ where: { id, status: 'processing' }, data, select: storySelect });
    return story ?? null;
  }

  async delete(id: string): Promise<void> {
    await this.prisma.story.deleteMany({ where: { id } });
  }

  findAllByAuthor(userId: string): Promise<Story[]> {
    return this.prisma.story.findMany({ where: { userId }, select: storySelect });
  }

  findActiveByAuthors(userIds: string[], now: Date): Promise<Story[]> {
    if (userIds.length === 0) return Promise.resolve([]);
    return this.prisma.story.findMany({
      where: { userId: { in: userIds }, ...active(now) },
      orderBy: [{ publishedAt: 'asc' }, { id: 'asc' }],
      select: storySelect,
    });
  }

  // Deux lectures indexées (stories actives des comptes, puis vues du lecteur parmi elles), regroupées ici : 30 stories
  // actives au plus par compte.
  async summarizeActive(userIds: string[], viewerId: string | null, now: Date): Promise<StoryAuthorSummary[]> {
    if (userIds.length === 0) return [];
    const stories = await this.prisma.story.findMany({
      where: { userId: { in: [...new Set(userIds)] }, ...active(now) },
      select: { id: true, userId: true, publishedAt: true },
    });
    const viewed = viewerId
      ? new Set(
          (
            await this.prisma.storyView.findMany({
              where: { userId: viewerId, storyId: { in: stories.map((story) => story.id) } },
              select: { storyId: true },
            })
          ).map((view) => view.storyId),
        )
      : new Set<string>();
    const byAuthor = new Map<string, StoryAuthorSummary>();
    for (const story of stories) {
      const summary = byAuthor.get(story.userId) ?? { userId: story.userId, storiesCount: 0, latestAt: story.publishedAt!, viewedCount: 0 };
      summary.storiesCount += 1;
      if (story.publishedAt! > summary.latestAt) summary.latestAt = story.publishedAt!;
      if (viewed.has(story.id)) summary.viewedCount += 1;
      byAuthor.set(story.userId, summary);
    }
    return [...byAuthor.values()];
  }

  async findViewerStates(viewerId: string, storyIds: string[]): Promise<Map<string, { liked: boolean }>> {
    if (storyIds.length === 0) return new Map();
    const views = await this.prisma.storyView.findMany({
      where: { userId: viewerId, storyId: { in: storyIds } },
      select: { storyId: true, likedAt: true },
    });
    return new Map(views.map((view) => [view.storyId, { liked: view.likedAt !== null }]));
  }

  async countStats(storyIds: string[], excludedUserIds: string[]): Promise<Map<string, StoryStats>> {
    if (storyIds.length === 0) return new Map();
    const rows = await this.prisma.storyView.groupBy({
      by: ['storyId'],
      where: { storyId: { in: storyIds }, ...(excludedUserIds.length > 0 ? { userId: { notIn: excludedUserIds } } : {}) },
      _count: { _all: true, likedAt: true },
    });
    return new Map(rows.map((row) => [row.storyId, { viewersCount: row._count._all, likesCount: row._count.likedAt }]));
  }

  // ON CONFLICT DO NOTHING : la première vue est gardée.
  async recordView(storyId: string, userId: string, at: Date): Promise<void> {
    await this.prisma.storyView.createMany({ data: [{ storyId, userId, viewedAt: at }], skipDuplicates: true });
  }

  async setLiked(storyId: string, userId: string, liked: boolean, at: Date): Promise<void> {
    if (!liked) {
      await this.prisma.storyView.updateMany({ where: { storyId, userId }, data: { likedAt: null } });
      return;
    }
    // Le like vaut vue : la ligne est créée si besoin ; un like déjà présent garde sa date.
    await this.prisma.storyView.createMany({ data: [{ storyId, userId, viewedAt: at, likedAt: at }], skipDuplicates: true });
    await this.prisma.storyView.updateMany({ where: { storyId, userId, likedAt: null }, data: { likedAt: at } });
  }

  // Pagination par clé (viewed_at, user_id), sur l'index (story_id, viewed_at).
  async listViews(storyId: string, excludedUserIds: string[], after: StoryViewPosition | null, limit: number): Promise<StoryView[]> {
    const rows = await this.prisma.storyView.findMany({
      where: {
        storyId,
        ...(excludedUserIds.length > 0 ? { userId: { notIn: excludedUserIds } } : {}),
        ...(after ? { OR: [{ viewedAt: { lt: after.viewedAt } }, { viewedAt: after.viewedAt, userId: { lt: after.userId } }] } : {}),
      },
      orderBy: [{ viewedAt: 'desc' }, { userId: 'desc' }],
      take: limit,
      select: { userId: true, viewedAt: true, likedAt: true },
    });
    return rows.map((row) => ({ userId: row.userId, viewedAt: row.viewedAt, liked: row.likedAt !== null }));
  }

  findExpired(now: Date, limit: number): Promise<Story[]> {
    return this.prisma.story.findMany({ where: { expiresAt: { lte: now } }, orderBy: { expiresAt: 'asc' }, take: limit, select: storySelect });
  }

  findUnpublishedCreatedBefore(createdBefore: Date, limit: number): Promise<Story[]> {
    return this.prisma.story.findMany({
      where: { status: { in: ['uploading', 'processing', 'failed'] }, createdAt: { lt: createdBefore } },
      orderBy: { createdAt: 'asc' },
      take: limit,
      select: storySelect,
    });
  }

  findStuckTranscodes(updatedBefore: Date, limit: number): Promise<Story[]> {
    return this.prisma.story.findMany({
      where: { status: 'processing', updatedAt: { lt: updatedBefore } },
      orderBy: { updatedAt: 'asc' },
      take: limit,
      select: storySelect,
    });
  }

  findByIds(ids: string[]): Promise<Story[]> {
    if (ids.length === 0) return Promise.resolve([]);
    return this.prisma.story.findMany({ where: { id: { in: ids } }, select: storySelect });
  }
}
