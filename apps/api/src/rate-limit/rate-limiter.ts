// Limites de débit (ADR-014 : compteurs dans Redis), partagées par les modules qui en ont besoin : envois de
// messages (messaging), échecs de connexion et inscriptions (auth), partages, réactions, commentaires, follows
// et vues (interactions), signalements (reports), envois de vidéos (videos). Voir ADR-030 et ADR-039. Port sans dépendance
// à NestJS ni à Redis : les couches domain/ et application/ des modules peuvent l'importer (ADR-003).
// Fenêtres fixes, partagées entre les instances de l'API. Clés préfixées par `ratelimit:` dans Redis.
// Stockage indisponible : l'action est permise (au pire, pas de limite le temps de la panne), et journalisée.

export interface RateLimitRule {
  limit: number;
  windowSeconds: number;
}

export abstract class RateLimiter {
  // Compte une tentative pour `key` si toutes les règles le permettent. Sinon, ne compte rien et renvoie
  // le délai (en secondes) avant la prochaine tentative possible.
  abstract consume(key: string, rules: RateLimitRule[]): Promise<number | null>;

  // Sans rien compter : délai (en secondes) avant la prochaine tentative possible si une règle est atteinte, sinon null.
  abstract check(key: string, rules: RateLimitRule[]): Promise<number | null>;

  // Compte une tentative, sans vérifier les règles (échec constaté après coup, comme un mauvais mot de passe).
  abstract hit(key: string, rules: RateLimitRule[]): Promise<void>;

  // Efface les compteurs des fenêtres en cours (connexion réussie).
  abstract reset(key: string, rules: RateLimitRule[]): Promise<void>;

  // Vrai la première fois pour `key` sur une période glissante de `seconds`, faux ensuite (dédoublonnage).
  abstract once(key: string, seconds: number): Promise<boolean>;
}

// Délai d'attente lisible, pour les messages d'erreur (« 45 s », « 12 min », « 3 h »).
export function formatRetryDelay(seconds: number): string {
  if (seconds < 60) return `${seconds} s`;
  if (seconds < 3600) return `${Math.ceil(seconds / 60)} min`;
  return `${Math.ceil(seconds / 3600)} h`;
}

// Fenêtre fixe en cours d'une règle : suffixe de clé et secondes avant sa fin.
export function currentWindow(rule: RateLimitRule, nowMs: number): { suffix: string; resetIn: number } {
  const now = nowMs / 1000;
  const index = Math.floor(now / rule.windowSeconds);
  return { suffix: `${rule.windowSeconds}:${index}`, resetIn: Math.max(1, Math.ceil((index + 1) * rule.windowSeconds - now)) };
}
