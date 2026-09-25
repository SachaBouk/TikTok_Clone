import { Injectable, Logger } from '@nestjs/common';
import { Redis } from 'ioredis';
import type { RateLimitRule } from '../domain/messaging';
import { RateLimiter } from '../domain/rate-limiter';

// Fenêtres fixes dans Redis (ADR-014), partagées entre les instances : un compteur par règle et par fenêtre,
// qui expire avec elle. Une tentative refusée n'est pas comptée : insister ne prolonge pas l'attente.
// Redis indisponible : l'envoi est permis (au pire, pas de limite le temps de la panne), et journalisé.
@Injectable()
export class RedisRateLimiter extends RateLimiter {
  private readonly logger = new Logger('RateLimiter');

  constructor(private readonly redis: Redis) {
    super();
  }

  async consume(key: string, rules: RateLimitRule[]): Promise<number | null> {
    const now = Date.now() / 1000;
    const windows = rules.map((rule) => {
      const index = Math.floor(now / rule.windowSeconds);
      return { rule, key: `ratelimit:${key}:${rule.windowSeconds}:${index}`, resetIn: Math.ceil((index + 1) * rule.windowSeconds - now) };
    });
    try {
      const counts = await this.redis.mget(...windows.map((w) => w.key));
      const exceeded = windows.filter((w, i) => Number(counts[i] ?? 0) >= w.rule.limit);
      if (exceeded.length > 0) return Math.max(...exceeded.map((w) => w.resetIn));
      const multi = this.redis.multi();
      for (const w of windows) multi.incr(w.key).expire(w.key, w.rule.windowSeconds + 1);
      await multi.exec();
      return null;
    } catch (error) {
      this.logger.warn(`Limite non vérifiée pour ${key} : ${(error as Error).message}`);
      return null;
    }
  }
}
