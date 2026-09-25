import { VideoCleanupQueue, type VideoFilesCleanup } from '../domain/cleanup-queue';

// Adaptateur en mémoire pour les tests : garde les nettoyages programmés, que le test exécute lui-même.
export class InMemoryVideoCleanupQueue extends VideoCleanupQueue {
  readonly scheduled: { cleanup: VideoFilesCleanup; delayMs: number }[] = [];

  async schedule(cleanups: VideoFilesCleanup[], delayMs: number): Promise<void> {
    for (const cleanup of cleanups) this.scheduled.push({ cleanup, delayMs });
  }
}
