import type { RateLimitRule } from './messaging';

// Limitation du nombre d'envois (anti-spam). Fenêtres fixes, partagées entre les instances de l'API.
export abstract class RateLimiter {
  // Compte une tentative pour `key` si toutes les règles le permettent. Sinon, ne compte rien et renvoie
  // le délai (en secondes) avant la prochaine tentative possible.
  abstract consume(key: string, rules: RateLimitRule[]): Promise<number | null>;
}
