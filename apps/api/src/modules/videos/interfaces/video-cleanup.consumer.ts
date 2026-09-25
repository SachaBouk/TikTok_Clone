import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Job, Worker } from 'bullmq';
import { queueConnection } from '../../../queue/queue-connection';
import { VideosService } from '../application/videos.service';
import type { VideoFilesCleanup } from '../domain/cleanup-queue';
import { VIDEO_CLEANUP_QUEUE } from '../infrastructure/bullmq-video-cleanup-queue';

// Consomme la file `video-cleanup` (ADR-012) : supprime du stockage les fichiers des vidéos supprimées.
// Point d'entrée au même titre qu'un controller, d'où sa place dans `interfaces/`.
@Injectable()
export class VideoCleanupConsumer implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger('VideoCleanup');
  private worker?: Worker<VideoFilesCleanup>;

  constructor(private readonly videos: VideosService) {}

  async onModuleInit() {
    this.worker = new Worker<VideoFilesCleanup>(VIDEO_CLEANUP_QUEUE, (job) => this.handle(job), {
      connection: queueConnection(),
      concurrency: 5,
    });
    this.worker.on('failed', (job, error) =>
      this.logger.warn(`Nettoyage de ${job?.data.videoId} en échec (tentative ${job?.attemptsMade}) : ${error.message}`),
    );
    await this.worker.waitUntilReady();
  }

  async onModuleDestroy() {
    await this.worker?.close();
  }

  private async handle({ data }: Job<VideoFilesCleanup>) {
    if (await this.videos.cleanupFiles(data)) this.logger.log(`Fichiers de la vidéo ${data.videoId} supprimés`);
    else this.logger.warn(`Vidéo ${data.videoId} toujours en base : fichiers conservés (suppression échouée ?)`);
  }
}
