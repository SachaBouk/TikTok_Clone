import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { TRANSCODE_ATTEMPTS, TRANSCODE_BACKOFF_DELAY_MS, TRANSCODE_QUEUE, type TranscodeJobData } from '@repo/shared';
import { Queue } from 'bullmq';
import { queueConnection } from '../../../queue/queue-connection';
import { TranscodingJob, TranscodingQueue } from '../domain/transcoding-queue';

// Publie les jobs de transcodage dans la queue BullMQ `video-transcode` (ADR-012), consommée par apps/worker.
@Injectable()
export class BullmqTranscodingQueue extends TranscodingQueue implements OnModuleDestroy {
  // Créée au premier envoi : BullMQ se connecte dès la construction d'une Queue, même en `lazyConnect`,
  // et l'export OpenAPI construit les modules sans Redis.
  private queue?: Queue<TranscodeJobData>;

  async enqueue(job: TranscodingJob): Promise<void> {
    this.queue ??= new Queue<TranscodeJobData>(TRANSCODE_QUEUE, { connection: queueConnection() });
    await this.queue.add(
      'transcode',
      { videoId: job.videoId, rawKey: job.rawKey, ...(job.coverKey ? { coverKey: job.coverKey } : {}) },
      {
        // Un job par vidéo : une nouvelle publication pour une vidéo déjà dans la file est ignorée.
        jobId: job.videoId,
        attempts: TRANSCODE_ATTEMPTS,
        backoff: { type: 'exponential', delay: TRANSCODE_BACKOFF_DELAY_MS },
        removeOnComplete: { age: 7 * 24 * 3600 },
        // Gardés 24 h pour le diagnostic. Tant qu'un job en échec existe, une republication est ignorée.
        removeOnFail: { age: 24 * 3600 },
      },
    );
  }

  async cancel(videoId: string): Promise<void> {
    this.queue ??= new Queue<TranscodeJobData>(TRANSCODE_QUEUE, { connection: queueConnection() });
    // 0 si le job est en cours (verrouillé) ou déjà absent : sans effet, voir le port.
    await this.queue.remove(videoId);
  }

  async onModuleDestroy() {
    await this.queue?.close();
  }
}
