import type { RateLimitRule } from '../../../rate-limit/rate-limiter';

// Limites des échecs de connexion par email et mot de passe (ADR-030). Seuls les échecs comptent ; au-delà,
// toute tentative est refusée (429), même avec le bon mot de passe, jusqu'à la fin de la fenêtre.
// - Par email : freine le forçage d'un compte. Une connexion réussie remet ce compteur à zéro.
// - Par adresse IP : freine l'essai d'un même mot de passe sur beaucoup de comptes.
export const LOGIN_EMAIL_RATE_LIMITS: RateLimitRule[] = [{ limit: 5, windowSeconds: 15 * 60 }];
export const LOGIN_IP_RATE_LIMITS: RateLimitRule[] = [{ limit: 20, windowSeconds: 15 * 60 }];

// Comptes créés par email et mot de passe, par adresse IP (ADR-039) : freine la création de comptes en masse.
// Seules les créations réussies comptent (un pseudo déjà pris ne coûte rien). Sign in with Apple n'est pas limité.
export const SIGNUP_IP_RATE_LIMITS: RateLimitRule[] = [
  { limit: 5, windowSeconds: 3600 },
  { limit: 20, windowSeconds: 24 * 3600 },
];
