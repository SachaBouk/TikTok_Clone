import { Injectable, Logger } from '@nestjs/common';
import { Redis } from 'ioredis';
import { SuspendedAccounts } from './suspended-accounts';

// Un ensemble Redis (ADR-025) : quelques comptes au plus, lus en entier par les listes qui les masquent.
const KEY = 'suspended:accounts';

@Injectable()
export class RedisSuspendedAccounts extends SuspendedAccounts {
  private readonly logger = new Logger('SuspendedAccounts');

  constructor(private readonly redis: Redis) {
    super();
  }

  async has(userId: string): Promise<boolean> {
    try {
      return (await this.redis.sismember(KEY, userId)) === 1;
    } catch (error) {
      this.logger.warn(`Suspension non vérifiée pour ${userId} : ${(error as Error).message}`);
      return false;
    }
  }

  async all(): Promise<Set<string>> {
    try {
      return new Set(await this.redis.smembers(KEY));
    } catch (error) {
      this.logger.warn(`Comptes suspendus non lus : ${(error as Error).message}`);
      return new Set();
    }
  }

  async add(userId: string): Promise<void> {
    await this.redis.sadd(KEY, userId);
  }

  async remove(userId: string): Promise<void> {
    await this.redis.srem(KEY, userId);
  }

  async replaceAll(userIds: string[]): Promise<void> {
    const multi = this.redis.multi().del(KEY);
    if (userIds.length > 0) multi.sadd(KEY, ...userIds);
    await multi.exec();
  }
}
