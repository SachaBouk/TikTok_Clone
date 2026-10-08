import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { STORY_TRANSCODE_QUEUE, TRANSCODE_ATTEMPTS, TRANSCODE_BACKOFF_DELAY_MS, type TranscodeJobData } from '@repo/shared';
import { Queue } from 'bullmq';
import { queueConnection } from '../../../queue/queue-connection';
import type { StoryFiles } from '../domain/story';
import { StoryLifecycleQueue, StoryTranscodingQueue } from '../domain/story-queues';

export const STORY_EXPIRY_QUEUE = 'story-expiry';
export const STORY_CLEANUP_QUEUE = 'story-cleanup';

export interface StoryExpiryJob {
  storyId: string;
}

// Les files sont créées au premier envoi : BullMQ se connecte dès la construction d'une Queue, même en `lazyConnect`, et
// l'export OpenAPI construit les modules sans Redis (voir CLAUDE.md).

// Transcodage des stories vidéo (ADR-051), consommé par apps/worker : même politique de relance que les vidéos.
@Injectable()
export class BullmqStoryTranscodingQueue extends StoryTranscodingQueue implements OnModuleDestroy {
  private queue?: Queue<TranscodeJobData>;

  async enqueue(job: { storyId: string; rawKey: string }): Promise<void> {
    await this.get().add(
      'transcode',
      { videoId: job.storyId, rawKey: job.rawKey },
      {
        // Un job par story : une nouvelle publication pour une story déjà dans la file est ignorée.
        jobId: job.storyId,
        attempts: TRANSCODE_ATTEMPTS,
        backoff: { type: 'exponential', delay: TRANSCODE_BACKOFF_DELAY_MS },
        removeOnComplete: { age: 24 * 3600 },
        removeOnFail: { age: 24 * 3600 },
      },
    );
  }

  async cancel(storyId: string): Promise<void> {
    // 0 si le job est en cours (verrouillé) ou déjà absent : sans effet, voir le port.
    await this.get().remove(storyId);
  }

  async onModuleDestroy() {
    await this.queue?.close();
  }

  private get(): Queue<TranscodeJobData> {
    return (this.queue ??= new Queue<TranscodeJobData>(STORY_TRANSCODE_QUEUE, { connection: queueConnection() }));
  }
}

// Expiration (job différé à l'échéance) et nettoyage des fichiers, produits et consommés par l'API (ADR-012).
@Injectable()
export class BullmqStoryLifecycleQueue extends StoryLifecycleQueue implements OnModuleDestroy {
  private expiry?: Queue<StoryExpiryJob>;
  private cleanup?: Queue<StoryFiles>;

  async scheduleExpiry(storyId: string, at: Date): Promise<void> {
    this.expiry ??= new Queue<StoryExpiryJob>(STORY_EXPIRY_QUEUE, { connection: queueConnection() });
    await this.expiry.add(
      'expire',
      { storyId },
      {
        jobId: storyId,
        delay: Math.max(0, at.getTime() - Date.now()),
        attempts: 5,
        backoff: { type: 'exponential', delay: 10_000 },
        removeOnComplete: true,
        removeOnFail: { age: 7 * 24 * 3600 },
      },
    );
  }

  async scheduleCleanup(files: StoryFiles[], delayMs: number): Promise<void> {
    this.cleanup ??= new Queue<StoryFiles>(STORY_CLEANUP_QUEUE, { connection: queueConnection() });
    await this.cleanup.addBulk(
      files.map((data) => ({
        name: 'cleanup',
        data,
        opts: {
          delay: delayMs,
          attempts: 5,
          backoff: { type: 'exponential', delay: 10_000 },
          removeOnComplete: { age: 24 * 3600 },
          // Gardés 7 jours : des fichiers restent à supprimer à la main.
          removeOnFail: { age: 7 * 24 * 3600 },
        },
      })),
    );
  }

  async onModuleDestroy() {
    await this.expiry?.close();
    await this.cleanup?.close();
  }
}
