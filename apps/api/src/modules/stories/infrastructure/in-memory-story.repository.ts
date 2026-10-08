import type { NewStory, Story, StoryAuthorSummary, StoryStats, StoryTranscodeOutcome, StoryView, StoryViewPosition } from '../domain/story';
import { StoryRepository } from '../domain/story.repository';

interface StoredView {
  storyId: string;
  userId: string;
  viewedAt: Date;
  likedAt: Date | null;
}

// Adaptateur en mémoire pour les tests du service. `updatedAt` est simulé pour la maintenance.
export class InMemoryStoryRepository extends StoryRepository {
  readonly stories = new Map<string, Story & { updatedAt: Date }>();
  readonly views: StoredView[] = [];

  constructor(private readonly now: () => Date = () => new Date()) {
    super();
  }

  async create(story: NewStory): Promise<Story> {
    const created = {
      ...story,
      status: 'uploading' as const,
      mediaUrl: null,
      thumbnailUrl: null,
      createdAt: this.now(),
      updatedAt: this.now(),
      publishedAt: null,
      expiresAt: null,
    };
    this.stories.set(story.id, created);
    return strip(created);
  }

  async findById(id: string): Promise<Story | null> {
    const story = this.stories.get(id);
    return story ? strip(story) : null;
  }

  async countActiveOrPending(userId: string, now: Date): Promise<number> {
    return [...this.stories.values()].filter(
      (s) => s.userId === userId && (s.status === 'uploading' || s.status === 'processing' || isActive(s, now)),
    ).length;
  }

  async markUploaded(id: string): Promise<Story | null> {
    return this.transition(id, 'uploading', { status: 'processing', uploadId: null });
  }

  async publishPhoto(id: string, mediaUrl: string, publishedAt: Date, expiresAt: Date): Promise<Story | null> {
    if (this.stories.get(id)?.mediaType !== 'photo') return null;
    return this.transition(id, 'uploading', { status: 'ready', uploadId: null, mediaUrl, thumbnailUrl: mediaUrl, publishedAt, expiresAt });
  }

  async markFailed(id: string): Promise<void> {
    const story = this.stories.get(id);
    if (story) Object.assign(story, { status: 'failed', uploadId: null, updatedAt: this.now() });
  }

  async finishTranscoding(id: string, outcome: StoryTranscodeOutcome, publishedAt: Date, expiresAt: Date): Promise<Story | null> {
    return this.transition(
      id,
      'processing',
      outcome.status === 'ready'
        ? { status: 'ready', mediaUrl: outcome.mediaUrl, thumbnailUrl: outcome.thumbnailUrl, publishedAt, expiresAt }
        : { status: 'failed' },
    );
  }

  // Cascade : ses vues partent avec elle.
  async delete(id: string): Promise<void> {
    this.stories.delete(id);
    for (let i = this.views.length - 1; i >= 0; i--) if (this.views[i].storyId === id) this.views.splice(i, 1);
  }

  async findAllByAuthor(userId: string): Promise<Story[]> {
    return [...this.stories.values()].filter((s) => s.userId === userId).map(strip);
  }

  async findActiveByAuthors(userIds: string[], now: Date): Promise<Story[]> {
    return [...this.stories.values()]
      .filter((s) => userIds.includes(s.userId) && isActive(s, now))
      .sort((a, b) => a.publishedAt!.getTime() - b.publishedAt!.getTime() || a.id.localeCompare(b.id))
      .map(strip);
  }

  async summarizeActive(userIds: string[], viewerId: string | null, now: Date): Promise<StoryAuthorSummary[]> {
    const byAuthor = new Map<string, StoryAuthorSummary>();
    for (const story of await this.findActiveByAuthors(userIds, now)) {
      const summary = byAuthor.get(story.userId) ?? { userId: story.userId, storiesCount: 0, latestAt: story.publishedAt!, viewedCount: 0 };
      summary.storiesCount += 1;
      if (story.publishedAt! > summary.latestAt) summary.latestAt = story.publishedAt!;
      if (viewerId && this.views.some((v) => v.storyId === story.id && v.userId === viewerId)) summary.viewedCount += 1;
      byAuthor.set(story.userId, summary);
    }
    return [...byAuthor.values()];
  }

  async findViewerStates(viewerId: string, storyIds: string[]): Promise<Map<string, { liked: boolean }>> {
    return new Map(
      this.views.filter((v) => v.userId === viewerId && storyIds.includes(v.storyId)).map((v) => [v.storyId, { liked: v.likedAt !== null }]),
    );
  }

  async countStats(storyIds: string[], excludedUserIds: string[]): Promise<Map<string, StoryStats>> {
    const stats = new Map<string, StoryStats>();
    for (const view of this.views) {
      if (!storyIds.includes(view.storyId) || excludedUserIds.includes(view.userId)) continue;
      const current = stats.get(view.storyId) ?? { viewersCount: 0, likesCount: 0 };
      current.viewersCount += 1;
      if (view.likedAt) current.likesCount += 1;
      stats.set(view.storyId, current);
    }
    return stats;
  }

  async recordView(storyId: string, userId: string, at: Date): Promise<void> {
    if (!this.find(storyId, userId)) this.views.push({ storyId, userId, viewedAt: at, likedAt: null });
  }

  async setLiked(storyId: string, userId: string, liked: boolean, at: Date): Promise<void> {
    const view = this.find(storyId, userId);
    if (!liked) {
      if (view) view.likedAt = null;
      return;
    }
    if (!view) this.views.push({ storyId, userId, viewedAt: at, likedAt: at });
    else view.likedAt ??= at;
  }

  async listViews(storyId: string, excludedUserIds: string[], after: StoryViewPosition | null, limit: number): Promise<StoryView[]> {
    return this.views
      .filter((v) => v.storyId === storyId && !excludedUserIds.includes(v.userId))
      .sort((a, b) => b.viewedAt.getTime() - a.viewedAt.getTime() || b.userId.localeCompare(a.userId))
      .filter((v) => !after || v.viewedAt < after.viewedAt || (v.viewedAt.getTime() === after.viewedAt.getTime() && v.userId < after.userId))
      .slice(0, limit)
      .map((v) => ({ userId: v.userId, viewedAt: v.viewedAt, liked: v.likedAt !== null }));
  }

  async findExpired(now: Date, limit: number): Promise<Story[]> {
    return [...this.stories.values()]
      .filter((s) => s.expiresAt !== null && s.expiresAt <= now)
      .slice(0, limit)
      .map(strip);
  }

  async findUnpublishedCreatedBefore(createdBefore: Date, limit: number): Promise<Story[]> {
    return [...this.stories.values()]
      .filter((s) => s.status !== 'ready' && s.createdAt < createdBefore)
      .slice(0, limit)
      .map(strip);
  }

  async findStuckTranscodes(updatedBefore: Date, limit: number): Promise<Story[]> {
    return [...this.stories.values()]
      .filter((s) => s.status === 'processing' && s.updatedAt < updatedBefore)
      .slice(0, limit)
      .map(strip);
  }

  async findByIds(ids: string[]): Promise<Story[]> {
    return ids.flatMap((id) => {
      const story = this.stories.get(id);
      return story ? [strip(story)] : [];
    });
  }

  private find(storyId: string, userId: string): StoredView | undefined {
    return this.views.find((v) => v.storyId === storyId && v.userId === userId);
  }

  private transition(id: string, from: Story['status'], change: Partial<Story>): Story | null {
    const story = this.stories.get(id);
    if (story?.status !== from) return null;
    Object.assign(story, change, { updatedAt: this.now() });
    return strip(story);
  }
}

function isActive(story: Story, now: Date): boolean {
  return story.status === 'ready' && story.expiresAt !== null && story.expiresAt > now;
}

function strip({ updatedAt: _updatedAt, ...story }: Story & { updatedAt: Date }): Story {
  return { ...story };
}
