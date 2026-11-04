import { Injectable, Logger } from '@nestjs/common';
import { Redis } from 'ioredis';
import { PlusMembers } from './plus-members';

// Un hash Redis : compte → échéance (millisecondes). Lu par lots (HMGET) pour les listes de comptes.
const KEY = 'plus:members';

@Injectable()
export class RedisPlusMembers extends PlusMembers {
  private readonly logger = new Logger('PlusMembers');

  constructor(private readonly redis: Redis) {
    super();
  }

  async expiryOf(userId: string): Promise<Date | null> {
    return (await this.expiriesOf([userId])).get(userId) ?? null;
  }

  async expiriesOf(userIds: string[]): Promise<Map<string, Date>> {
    if (userIds.length === 0) return new Map();
    try {
      const values = await this.redis.hmget(KEY, ...userIds);
      const expiries = new Map<string, Date>();
      values.forEach((value, index) => {
        if (value !== null && Number.isFinite(Number(value))) expiries.set(userIds[index], new Date(Number(value)));
      });
      return expiries;
    } catch (error) {
      this.logger.warn(`Abonnements non lus : ${(error as Error).message}`);
      return new Map();
    }
  }

  async set(userId: string, expiresAt: Date | null): Promise<void> {
    if (expiresAt) await this.redis.hset(KEY, userId, String(expiresAt.getTime()));
    else await this.redis.hdel(KEY, userId);
  }

  async replaceAll(entries: { userId: string; expiresAt: Date }[]): Promise<void> {
    const multi = this.redis.multi().del(KEY);
    if (entries.length > 0) multi.hset(KEY, Object.fromEntries(entries.map((e) => [e.userId, String(e.expiresAt.getTime())])));
    await multi.exec();
  }
}
