import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { Queue } from 'bullmq';
import { queueConnection } from '../../../queue/queue-connection';
import { VideoCleanupQueue, type VideoFilesCleanup } from '../domain/cleanup-queue';

export const VIDEO_CLEANUP_QUEUE = 'video-cleanup';

// File BullMQ `video-cleanup`, produite et consommée par l'API (VideoCleanupConsumer, ADR-012).
@Injectable()
export class BullmqVideoCleanupQueue extends VideoCleanupQueue implements OnModuleDestroy {
  // Créée au premier envoi (piège BullMQ : connexion dès la construction, voir CLAUDE.md).
  private queue?: Queue<VideoFilesCleanup>;

  // Contrairement aux notifications push, une erreur est propagée : la suppression ne doit pas avoir lieu
  // si le nettoyage de ses fichiers n'a pas pu être programmé.
  async schedule(cleanups: VideoFilesCleanup[], delayMs: number): Promise<void> {
    this.queue ??= new Queue<VideoFilesCleanup>(VIDEO_CLEANUP_QUEUE, { connection: queueConnection() });
    await this.queue.addBulk(
      cleanups.map((data) => ({
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
    await this.queue?.close();
  }
}
