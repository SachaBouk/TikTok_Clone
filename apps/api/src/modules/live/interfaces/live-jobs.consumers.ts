import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Job, Queue, Worker } from 'bullmq';
import { queueConnection } from '../../../queue/queue-connection';
import { LiveService } from '../application/live.service';
import { HOST_CHECK_JOB, LIVE_LIFECYCLE_QUEUE, type LiveLifecycleJob, TIME_LIMIT_JOB } from '../infrastructure/bullmq-live-lifecycle.queue';

// Points d'entrée des files BullMQ du live (ADR-012, ADR-053), au même titre qu'un controller. Workers créés dans
// `onModuleInit` (piège BullMQ : connexion dès la construction, voir CLAUDE.md).

// Fin à la durée maximale, et vérification que l'auteur est (re)venu dans la salle.
@Injectable()
export class LiveLifecycleConsumer implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger('LiveLifecycle');
  private worker?: Worker<LiveLifecycleJob>;

  constructor(private readonly lives: LiveService) {}

  async onModuleInit() {
    this.worker = new Worker<LiveLifecycleJob>(LIVE_LIFECYCLE_QUEUE, (job) => this.handle(job), { connection: queueConnection(), concurrency: 5 });
    this.worker.on('failed', (job, error) => this.logger.warn(`Job ${job?.name} du live ${job?.data.liveId} en échec : ${error.message}`));
    await this.worker.waitUntilReady();
  }

  async onModuleDestroy() {
    await this.worker?.close();
  }

  private async handle({ name, data }: Job<LiveLifecycleJob>) {
    if (name === TIME_LIMIT_JOB && (await this.lives.reachTimeLimit(data.liveId))) this.logger.log(`Live ${data.liveId} arrêté : durée maximale`);
    if (name === HOST_CHECK_JOB && (await this.lives.checkHost(data.liveId))) this.logger.log(`Live ${data.liveId} arrêté : auteur déconnecté`);
  }
}

export const LIVE_MAINTENANCE_QUEUE = 'live-maintenance';
const SCHEDULER_ID = 'live-maintenance';
const EVERY_MS = 5 * 60 * 1000;

// Maintenance toutes les 5 minutes (job scheduler BullMQ : une seule exécution par échéance, même avec plusieurs
// instances de l'API).
@Injectable()
export class LiveMaintenanceScheduler implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger('LiveMaintenance');
  private queue?: Queue;
  private worker?: Worker;

  constructor(private readonly lives: LiveService) {}

  async onModuleInit() {
    this.queue = new Queue(LIVE_MAINTENANCE_QUEUE, { connection: queueConnection() });
    await this.queue.upsertJobScheduler(SCHEDULER_ID, { every: EVERY_MS }, { name: 'run' });
    this.worker = new Worker(LIVE_MAINTENANCE_QUEUE, () => this.run(), { connection: queueConnection() });
    await this.worker.waitUntilReady();
  }

  async onModuleDestroy() {
    await this.worker?.close();
    await this.queue?.close();
  }

  private async run() {
    const report = await this.lives.runMaintenance();
    if (report.ended) this.logger.log(`${report.ended} live(s) arrêté(s) par la maintenance`);
    if (report.hostChecks) this.logger.log(`${report.hostChecks} auteur(s) absent(s) de leur salle : vérification programmée`);
    return report;
  }
}
