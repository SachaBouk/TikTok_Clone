import type { StoryFiles } from '../domain/story';
import { StoryLifecycleQueue, StoryTranscodingQueue } from '../domain/story-queues';

// Adaptateurs en mémoire pour les tests : gardent ce qui a été programmé, que le test exécute lui-même.
export class InMemoryStoryTranscodingQueue extends StoryTranscodingQueue {
  readonly jobs: { storyId: string; rawKey: string }[] = [];
  readonly cancelled: string[] = [];

  async enqueue(job: { storyId: string; rawKey: string }): Promise<void> {
    this.jobs.push(job);
  }

  async cancel(storyId: string): Promise<void> {
    this.cancelled.push(storyId);
  }
}

export class InMemoryStoryLifecycleQueue extends StoryLifecycleQueue {
  readonly expiries = new Map<string, Date>();
  readonly cleanups: { files: StoryFiles; delayMs: number }[] = [];
  failExpiry = false;

  async scheduleExpiry(storyId: string, at: Date): Promise<void> {
    if (this.failExpiry) throw new Error('Redis indisponible');
    if (!this.expiries.has(storyId)) this.expiries.set(storyId, at);
  }

  async scheduleCleanup(files: StoryFiles[], delayMs: number): Promise<void> {
    for (const file of files) this.cleanups.push({ files: file, delayMs });
  }
}
