import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { TRANSCODE_RESULTS_QUEUE, type TranscodeResult } from '@repo/shared';
import { Job, Worker } from 'bullmq';
import { queueConnection } from '../../../queue/queue-connection';
import { VideosService } from '../application/videos.service';
import type { TranscodeOutcome } from '../domain/video';

// Consomme les résultats publiés par apps/worker (ADR-012) : seule l'API écrit en base (ADR-003).
// Point d'entrée au même titre qu'un controller, d'où sa place dans `interfaces/`.
// Si l'API est arrêtée, les résultats attendent dans Redis et sont appliqués au redémarrage.
@Injectable()
export class TranscodeResultsConsumer implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger('TranscodeResults');
  private worker?: Worker<TranscodeResult>;

  constructor(private readonly videos: VideosService) {}

  async onModuleInit() {
    this.worker = new Worker<TranscodeResult>(TRANSCODE_RESULTS_QUEUE, (job) => this.handle(job), {
      connection: queueConnection(),
      concurrency: 5,
    });
    // Échoue au démarrage si Redis est injoignable.
    await this.worker.waitUntilReady();
  }

  async onModuleDestroy() {
    await this.worker?.close();
  }

  private async handle({ data }: Job<TranscodeResult>) {
    const applied = await this.videos.applyTranscodeResult(data.videoId, toOutcome(data));
    if (data.status === 'failed') this.logger.warn(`Transcodage en échec pour ${data.videoId} : ${data.reason}`);
    if (!applied) this.logger.log(`Résultat ignoré pour ${data.videoId} (vidéo plus en processing)`);
  }
}

function toOutcome(result: TranscodeResult): TranscodeOutcome {
  return result.status === 'ready'
    ? { status: 'ready', hlsUrl: result.hlsUrl, thumbnailUrl: result.thumbnailUrl }
    : { status: 'failed' };
}
