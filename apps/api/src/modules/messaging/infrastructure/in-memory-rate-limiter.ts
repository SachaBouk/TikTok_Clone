import type { RateLimitRule } from '../domain/messaging';
import { RateLimiter } from '../domain/rate-limiter';

// Adaptateur en mémoire pour les tests : mêmes fenêtres fixes que RedisRateLimiter, horloge injectable.
export class InMemoryRateLimiter extends RateLimiter {
  private readonly counters = new Map<string, number>();

  constructor(private readonly now: () => number = () => Date.now()) {
    super();
  }

  async consume(key: string, rules: RateLimitRule[]): Promise<number | null> {
    const now = this.now() / 1000;
    const windows = rules.map((rule) => {
      const index = Math.floor(now / rule.windowSeconds);
      return { rule, key: `${key}:${rule.windowSeconds}:${index}`, resetIn: Math.ceil((index + 1) * rule.windowSeconds - now) };
    });
    const exceeded = windows.filter((w) => (this.counters.get(w.key) ?? 0) >= w.rule.limit);
    if (exceeded.length > 0) return Math.max(...exceeded.map((w) => w.resetIn));
    for (const w of windows) this.counters.set(w.key, (this.counters.get(w.key) ?? 0) + 1);
    return null;
  }
}
