import { createHash } from 'node:crypto';
import type { AuthTokensDto } from '@repo/shared';

// Résultat d'un rafraîchissement : nouveaux jetons, ou session refusée par l'API (expirée, révoquée).
// Une API injoignable n'est pas un refus : la promesse est rejetée, la session est gardée.
export type RefreshOutcome = { kind: 'refreshed'; tokens: AuthTokensDto } | { kind: 'rejected' };

// Durée pendant laquelle le résultat d'un rafraîchissement est resservi aux requêtes qui présentent
// encore l'ancien refresh token (le navigateur n'a pas encore reçu les nouveaux cookies).
export const REFRESH_REUSE_WINDOW_MS = 30_000;

// Un seul rafraîchissement par refresh token. L'API fait tourner le refresh token à chaque usage et traite
// le réemploi d'un token déjà utilisé comme un vol : elle révoque alors toute la session (ADR-010). Or le
// navigateur envoie souvent plusieurs requêtes à la fois (préchargement des liens, Server Action) avec le
// même cookie : elles doivent toutes recevoir le résultat du même appel.
// Limite : l'état est propre au processus ; avec plusieurs instances du backoffice, il faudrait un magasin partagé.
export function createRefresher(refresh: (refreshToken: string) => Promise<RefreshOutcome>, now: () => number = Date.now) {
  const recent = new Map<string, { outcome: Promise<RefreshOutcome>; settledAt: number | null }>();

  return function refreshOnce(refreshToken: string): Promise<RefreshOutcome> {
    const time = now();
    for (const [key, entry] of recent) {
      if (entry.settledAt !== null && time - entry.settledAt > REFRESH_REUSE_WINDOW_MS) recent.delete(key);
    }

    const key = createHash('sha256').update(refreshToken).digest('hex');
    const existing = recent.get(key);
    if (existing) return existing.outcome;

    const entry: { outcome: Promise<RefreshOutcome>; settledAt: number | null } = { outcome: refresh(refreshToken), settledAt: null };
    recent.set(key, entry);
    entry.outcome.then(
      () => {
        entry.settledAt = now();
      },
      // API injoignable : rien n'a été consommé, la prochaine requête réessaie.
      () => recent.delete(key),
    );
    return entry.outcome;
  };
}
