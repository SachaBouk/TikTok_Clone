import { currentWindow, RateLimiter, type RateLimitRule } from './rate-limiter';

// Adaptateur en mémoire pour les tests : mêmes fenêtres fixes que RedisRateLimiter, horloge injectable.
export class InMemoryRateLimiter extends RateLimiter {
  private readonly counters = new Map<string, number>();
  // Clé → fin de la période (ms) de `once`.
  private readonly claims = new Map<string, number>();

  constructor(private readonly now: () => number = () => Date.now()) {
    super();
  }

  async consume(key: string, rules: RateLimitRule[]): Promise<number | null> {
    const retryAfter = await this.check(key, rules);
    if (retryAfter !== null) return retryAfter;
    await this.hit(key, rules);
    return null;
  }

  async check(key: string, rules: RateLimitRule[]): Promise<number | null> {
    const exceeded = this.windows(key, rules).filter((w) => (this.counters.get(w.key) ?? 0) >= w.rule.limit);
    return exceeded.length > 0 ? Math.max(...exceeded.map((w) => w.resetIn)) : null;
  }

  async hit(key: string, rules: RateLimitRule[]): Promise<void> {
    for (const w of this.windows(key, rules)) this.counters.set(w.key, (this.counters.get(w.key) ?? 0) + 1);
  }

  async reset(key: string, rules: RateLimitRule[]): Promise<void> {
    for (const w of this.windows(key, rules)) this.counters.delete(w.key);
  }

  async once(key: string, seconds: number): Promise<boolean> {
    const now = this.now();
    if ((this.claims.get(key) ?? 0) > now) return false;
    this.claims.set(key, now + seconds * 1000);
    return true;
  }

  private windows(key: string, rules: RateLimitRule[]) {
    const now = this.now();
    return rules.map((rule) => {
      const window = currentWindow(rule, now);
      return { rule, key: `${key}:${window.suffix}`, resetIn: window.resetIn };
    });
  }
}
