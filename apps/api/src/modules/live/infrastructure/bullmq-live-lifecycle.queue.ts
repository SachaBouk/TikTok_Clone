import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { Queue } from 'bullmq';
import { queueConnection } from '../../../queue/queue-connection';
import { LiveLifecycleQueue } from '../domain/live-media';

export const LIVE_LIFECYCLE_QUEUE = 'live-lifecycle';

export interface LiveLifecycleJob {
  liveId: string;
}

// Noms des jobs de la file : fin à la durée maximale, vérification de la présence de l'auteur.
export const TIME_LIMIT_JOB = 'timeLimit';
export const HOST_CHECK_JOB = 'hostCheck';

// Identifiant d'un job : un par live et par nom. Piège BullMQ : un identifiant choisi ne peut pas contenir « : »
// (l'ajout échoue).
export function lifecycleJobId(name: string, liveId: string): string {
  return `${name}-${liveId}`;
}

// Jobs différés du live (ADR-053), produits et consommés par l'API. File créée au premier usage (piège BullMQ, voir
// CLAUDE.md).
@Injectable()
export class BullmqLiveLifecycleQueue extends LiveLifecycleQueue implements OnModuleDestroy {
  private readonly logger = new Logger(BullmqLiveLifecycleQueue.name);
  private queue?: Queue<LiveLifecycleJob>;

  async scheduleTimeLimit(liveId: string, at: Date): Promise<void> {
    await this.logged(liveId, () =>
      this.get().add(
        TIME_LIMIT_JOB,
        { liveId },
        { jobId: lifecycleJobId(TIME_LIMIT_JOB, liveId), delay: Math.max(0, at.getTime() - Date.now()), ...JOB_OPTIONS },
      ),
    );
  }

  // Une seule vérification par live : la précédente, si elle attend encore, est remplacée (départ puis retour de l'auteur).
  async scheduleHostCheck(liveId: string, delayMs: number): Promise<void> {
    const queue = this.get();
    const jobId = lifecycleJobId(HOST_CHECK_JOB, liveId);
    await this.logged(liveId, async () => {
      await queue.remove(jobId);
      await queue.add(HOST_CHECK_JOB, { liveId }, { jobId, delay: delayMs, ...JOB_OPTIONS });
    });
  }

  async onModuleDestroy() {
    await this.queue?.close();
  }

  // Le service rattrape l'échec (maintenance) sans le dire : il est journalisé ici.
  private async logged(liveId: string, run: () => Promise<unknown>): Promise<void> {
    try {
      await run();
    } catch (error) {
      this.logger.warn(`Job du live ${liveId} non programmé : ${String(error)}`);
      throw error;
    }
  }

  private get(): Queue<LiveLifecycleJob> {
    return (this.queue ??= new Queue<LiveLifecycleJob>(LIVE_LIFECYCLE_QUEUE, { connection: queueConnection() }));
  }
}

const JOB_OPTIONS = {
  attempts: 5,
  backoff: { type: 'exponential', delay: 5_000 },
  removeOnComplete: true,
  removeOnFail: { age: 7 * 24 * 3600 },
} as const;
