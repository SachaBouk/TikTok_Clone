import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { Queue } from 'bullmq';
import { queueConnection } from '../../../queue/queue-connection';
import type { PushDevice, PushMessage } from '../domain/push';
import { PushQueue } from '../domain/push-queue';

export const PUSH_QUEUE = 'push-notifications';
export type PushJobData = { device: PushDevice; message: PushMessage };

// File BullMQ `push-notifications`, produite et consommée par l'API (PushDeliveryConsumer) : un job par appareil.
@Injectable()
export class BullmqPushQueue extends PushQueue implements OnModuleDestroy {
  private readonly logger = new Logger('PushQueue');
  // Créée au premier envoi (piège BullMQ : connexion dès la construction, voir CLAUDE.md).
  private queue?: Queue<PushJobData>;

  async enqueue(delivery: PushJobData): Promise<void> {
    try {
      this.queue ??= new Queue<PushJobData>(PUSH_QUEUE, { connection: queueConnection() });
      await this.queue.add('push', delivery, {
        attempts: 3,
        backoff: { type: 'exponential', delay: 5_000 },
        removeOnComplete: { age: 24 * 3600 },
        removeOnFail: { age: 24 * 3600 },
      });
    } catch (error) {
      this.logger.warn(`Notification push non mise en file : ${(error as Error).message}`);
    }
  }

  async onModuleDestroy() {
    await this.queue?.close();
  }
}
