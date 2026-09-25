import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Job, Worker } from 'bullmq';
import { queueConnection } from '../../../queue/queue-connection';
import { PushService } from '../application/push.service';
import { PUSH_QUEUE, type PushJobData } from '../infrastructure/bullmq-push-queue';

// Consomme la file `push-notifications` (ADR-012) : un job par appareil, 3 tentatives en cas d'échec temporaire.
// Point d'entrée au même titre qu'un controller, d'où sa place dans `interfaces/`.
@Injectable()
export class PushDeliveryConsumer implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger('PushDelivery');
  private worker?: Worker<PushJobData>;

  constructor(private readonly push: PushService) {}

  async onModuleInit() {
    this.worker = new Worker<PushJobData>(PUSH_QUEUE, (job) => this.handle(job), { connection: queueConnection(), concurrency: 10 });
    this.worker.on('failed', (job, error) => this.logger.warn(`Notification push en échec (tentative ${job?.attemptsMade}) : ${error.message}`));
    await this.worker.waitUntilReady();
  }

  async onModuleDestroy() {
    await this.worker?.close();
  }

  private async handle({ data }: Job<PushJobData>) {
    const result = await this.push.deliver(data.device, data.message);
    if (result === 'invalidToken') this.logger.log(`Token APNs refusé, appareil oublié : ${data.device.token.slice(0, 8)}…`);
  }
}
