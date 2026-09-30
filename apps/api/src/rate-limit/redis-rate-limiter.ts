import { Injectable, Logger } from '@nestjs/common';
import { Redis } from 'ioredis';
import { currentWindow, RateLimiter, type RateLimitRule } from './rate-limiter';

// Fenêtres fixes dans Redis (ADR-014), partagées entre les instances : un compteur par règle et par fenêtre,
// qui expire avec elle. Une tentative refusée n'est pas comptée : insister ne prolonge pas l'attente.
// Redis indisponible : l'action est permise, et journalisée.
@Injectable()
export class RedisRateLimiter extends RateLimiter {
  private readonly logger = new Logger('RateLimiter');

  constructor(private readonly redis: Redis) {
    super();
  }

  async consume(key: string, rules: RateLimitRule[]): Promise<number | null> {
    const retryAfter = await this.check(key, rules);
    if (retryAfter !== null) return retryAfter;
    await this.hit(key, rules);
    return null;
  }

  async check(key: string, rules: RateLimitRule[]): Promise<number | null> {
    const windows = this.windows(key, rules);
    try {
      const counts = await this.redis.mget(...windows.map((w) => w.key));
      const exceeded = windows.filter((w, i) => Number(counts[i] ?? 0) >= w.rule.limit);
      return exceeded.length > 0 ? Math.max(...exceeded.map((w) => w.resetIn)) : null;
    } catch (error) {
      this.logger.warn(`Limite non vérifiée pour ${key} : ${(error as Error).message}`);
      return null;
    }
  }

  async hit(key: string, rules: RateLimitRule[]): Promise<void> {
    try {
      const multi = this.redis.multi();
      for (const w of this.windows(key, rules)) multi.incr(w.key).expire(w.key, w.rule.windowSeconds + 1);
      await multi.exec();
    } catch (error) {
      this.logger.warn(`Tentative non comptée pour ${key} : ${(error as Error).message}`);
    }
  }

  async reset(key: string, rules: RateLimitRule[]): Promise<void> {
    try {
      await this.redis.del(...this.windows(key, rules).map((w) => w.key));
    } catch (error) {
      this.logger.warn(`Compteurs non effacés pour ${key} : ${(error as Error).message}`);
    }
  }

  async once(key: string, seconds: number): Promise<boolean> {
    try {
      return (await this.redis.set(`ratelimit:${key}`, '1', 'EX', seconds, 'NX')) === 'OK';
    } catch (error) {
      this.logger.warn(`Dédoublonnage non vérifié pour ${key} : ${(error as Error).message}`);
      return true;
    }
  }

  private windows(key: string, rules: RateLimitRule[]) {
    const now = Date.now();
    return rules.map((rule) => {
      const window = currentWindow(rule, now);
      return { rule, key: `ratelimit:${key}:${window.suffix}`, resetIn: window.resetIn };
    });
  }
}
