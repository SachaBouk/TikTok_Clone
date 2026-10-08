import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { STORY_TRANSCODE_RESULTS_QUEUE, type TranscodeResult } from '@repo/shared';
import { Job, Queue, Worker } from 'bullmq';
import { queueConnection } from '../../../queue/queue-connection';
import { StoriesService } from '../application/stories.service';
import type { StoryFiles } from '../domain/story';
import { STORY_CLEANUP_QUEUE, STORY_EXPIRY_QUEUE, type StoryExpiryJob } from '../infrastructure/bullmq-story-queues';

// Points d'entrée des files BullMQ des stories (ADR-012, ADR-051), au même titre qu'un controller. Workers créés dans
// `onModuleInit` (piège BullMQ : connexion dès la construction, voir CLAUDE.md).

// Résultats du transcodage publiés par apps/worker : seule l'API écrit en base (ADR-003).
@Injectable()
export class StoryTranscodeResultsConsumer implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger('StoryTranscodeResults');
  private worker?: Worker<TranscodeResult>;

  constructor(private readonly stories: StoriesService) {}

  async onModuleInit() {
    this.worker = new Worker<TranscodeResult>(STORY_TRANSCODE_RESULTS_QUEUE, (job) => this.handle(job), {
      connection: queueConnection(),
      concurrency: 5,
    });
    await this.worker.waitUntilReady();
  }

  async onModuleDestroy() {
    await this.worker?.close();
  }

  private async handle({ data }: Job<TranscodeResult>) {
    const applied = await this.stories.applyTranscodeResult(
      data.videoId,
      data.status === 'ready' ? { status: 'ready', mediaUrl: data.hlsUrl, thumbnailUrl: data.thumbnailUrl } : { status: 'failed' },
    );
    if (data.status === 'failed') this.logger.warn(`Transcodage de la story ${data.videoId} en échec : ${data.reason}`);
    if (!applied) this.logger.log(`Résultat ignoré pour la story ${data.videoId} (plus en processing)`);
  }
}

// Échéance d'une story (job différé programmé à sa publication) : suppression.
@Injectable()
export class StoryExpiryConsumer implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger('StoryExpiry');
  private worker?: Worker<StoryExpiryJob>;

  constructor(private readonly stories: StoriesService) {}

  async onModuleInit() {
    this.worker = new Worker<StoryExpiryJob>(STORY_EXPIRY_QUEUE, (job) => this.handle(job), { connection: queueConnection(), concurrency: 5 });
    this.worker.on('failed', (job, error) => this.logger.warn(`Expiration de la story ${job?.data.storyId} en échec : ${error.message}`));
    await this.worker.waitUntilReady();
  }

  async onModuleDestroy() {
    await this.worker?.close();
  }

  private async handle({ data }: Job<StoryExpiryJob>) {
    if (await this.stories.expire(data.storyId)) this.logger.log(`Story ${data.storyId} expirée et supprimée`);
  }
}

// Nettoyage des fichiers des stories supprimées.
@Injectable()
export class StoryCleanupConsumer implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger('StoryCleanup');
  private worker?: Worker<StoryFiles>;

  constructor(private readonly stories: StoriesService) {}

  async onModuleInit() {
    this.worker = new Worker<StoryFiles>(STORY_CLEANUP_QUEUE, (job) => this.handle(job), { connection: queueConnection(), concurrency: 5 });
    this.worker.on('failed', (job, error) =>
      this.logger.warn(`Nettoyage de la story ${job?.data.storyId} en échec (tentative ${job?.attemptsMade}) : ${error.message}`),
    );
    await this.worker.waitUntilReady();
  }

  async onModuleDestroy() {
    await this.worker?.close();
  }

  private async handle({ data }: Job<StoryFiles>) {
    if (!(await this.stories.cleanupFiles(data)))
      this.logger.warn(`Story ${data.storyId} toujours en base : fichiers conservés (suppression échouée ?)`);
  }
}

export const STORIES_MAINTENANCE_QUEUE = 'stories-maintenance';
const SCHEDULER_ID = 'stories-maintenance';
const EVERY_MS = 15 * 60 * 1000;

// Maintenance toutes les 15 minutes via un job scheduler BullMQ : une seule exécution par échéance, même avec plusieurs
// instances de l'API.
@Injectable()
export class StoriesMaintenanceScheduler implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger('StoriesMaintenance');
  private queue?: Queue;
  private worker?: Worker;

  constructor(private readonly stories: StoriesService) {}

  async onModuleInit() {
    this.queue = new Queue(STORIES_MAINTENANCE_QUEUE, { connection: queueConnection() });
    await this.queue.upsertJobScheduler(SCHEDULER_ID, { every: EVERY_MS }, { name: 'run' });
    this.worker = new Worker(STORIES_MAINTENANCE_QUEUE, () => this.run(), { connection: queueConnection() });
    await this.worker.waitUntilReady();
  }

  async onModuleDestroy() {
    await this.worker?.close();
    await this.queue?.close();
  }

  private async run() {
    const report = await this.stories.runMaintenance();
    if (report.expired || report.purged || report.requeued) {
      this.logger.log(
        `${report.expired} story(s) expirée(s), ${report.purged} non publiée(s) supprimée(s), ${report.requeued} transcodage(s) relancé(s)`,
      );
    }
    return report;
  }
}
