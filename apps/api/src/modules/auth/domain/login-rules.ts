import type { RateLimitRule } from '../../../rate-limit/rate-limiter';

// Limites des échecs de connexion par identifiant et mot de passe (ADR-030, ADR-055). Seuls les échecs comptent ;
// au-delà, toute tentative est refusée (429), même avec le bon mot de passe, jusqu'à la fin de la fenêtre.
// - Par compte (ou par identifiant inconnu) : freine le forçage d'un compte, qu'on le désigne par son email ou son
//   pseudo. Une connexion réussie remet ce compteur à zéro.
// - Par adresse IP : freine l'essai d'un même mot de passe sur beaucoup de comptes.
export const LOGIN_ACCOUNT_RATE_LIMITS: RateLimitRule[] = [{ limit: 5, windowSeconds: 15 * 60 }];
export const LOGIN_IP_RATE_LIMITS: RateLimitRule[] = [{ limit: 20, windowSeconds: 15 * 60 }];

// Identifiant de connexion (ADR-055) : un email (contient « @ » ailleurs qu'en tête), sinon un pseudo, dont le « @ »
// initial est ignoré. Les pseudos ne contiennent jamais « @ ». Normalisé en minuscules, sans espaces autour.
export type LoginIdentifier = { kind: 'email'; value: string } | { kind: 'username'; value: string };

export function parseLoginIdentifier(identifier: string): LoginIdentifier {
  const trimmed = identifier.trim().toLowerCase();
  if (trimmed.indexOf('@', 1) > 0) return { kind: 'email', value: trimmed };
  return { kind: 'username', value: trimmed.replace(/^@/, '') };
}

// Comptes créés par email et mot de passe, par adresse IP (ADR-039) : freine la création de comptes en masse.
// Seules les créations réussies comptent (un pseudo déjà pris ne coûte rien). Sign in with Apple n'est pas limité.
export const SIGNUP_IP_RATE_LIMITS: RateLimitRule[] = [
  { limit: 5, windowSeconds: 3600 },
  { limit: 20, windowSeconds: 24 * 3600 },
];
