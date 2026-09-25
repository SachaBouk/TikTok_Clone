import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Queue, Worker } from 'bullmq';
import { queueConnection } from '../../../queue/queue-connection';
import { VideosService } from '../application/videos.service';

export const VIDEOS_MAINTENANCE_QUEUE = 'videos-maintenance';
const SCHEDULER_ID = 'videos-maintenance';
const EVERY_MS = 15 * 60 * 1000;

// Maintenance planifiée toutes les 15 minutes via un job scheduler BullMQ (ADR-012) :
// une seule exécution par échéance, même avec plusieurs instances de l'API.
@Injectable()
export class VideosMaintenanceScheduler implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger('VideosMaintenance');
  private queue?: Queue;
  private worker?: Worker;

  constructor(private readonly videos: VideosService) {}

  async onModuleInit() {
    this.queue = new Queue(VIDEOS_MAINTENANCE_QUEUE, { connection: queueConnection() });
    // Idempotent : crée ou met à jour l'échéancier à chaque démarrage.
    await this.queue.upsertJobScheduler(SCHEDULER_ID, { every: EVERY_MS }, { name: 'run' });

    this.worker = new Worker(VIDEOS_MAINTENANCE_QUEUE, () => this.run(), { connection: queueConnection() });
    await this.worker.waitUntilReady();
  }

  async onModuleDestroy() {
    await this.worker?.close();
    await this.queue?.close();
  }

  private async run() {
    const purged = await this.videos.purgeAbandonedUploads();
    const requeued = await this.videos.requeueStuckTranscodes();
    if (purged || requeued) {
      this.logger.log(`${purged} upload(s) abandonné(s) supprimé(s), ${requeued} transcodage(s) relancé(s)`);
    }
    return { purged, requeued };
  }
}
