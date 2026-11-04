import type { RateLimitRule } from '../../../rate-limit/rate-limiter';

// Catalogue des cadeaux (ADR-050), dans le code (choix du développeur) : un changement passe par un déploiement.
// Chaque cadeau envoyé garde son code et le prix payé : modifier le catalogue ne réécrit pas l'historique. L'app
// affiche l'emoji reçu de l'API ; un code retiré depuis s'affiche « 🎁 Cadeau ».
export interface GiftCatalogItem {
  code: string;
  name: string;
  emoji: string;
  // Prix en jetons.
  price: number;
  // Réservé aux abonnés « Plus » (ADR-073).
  plusOnly: boolean;
}

export const GIFT_CATALOG: readonly GiftCatalogItem[] = [
  { code: 'rose', name: 'Rose', emoji: '🌹', price: 1, plusOnly: false },
  { code: 'heart', name: 'Cœur', emoji: '❤️', price: 5, plusOnly: false },
  { code: 'star', name: 'Étoile', emoji: '⭐', price: 10, plusOnly: false },
  // Cadeaux exclusifs des abonnés « Plus » (ADR-073).
  { code: 'unicorn', name: 'Licorne', emoji: '🦄', price: 20, plusOnly: true },
  { code: 'crown', name: 'Couronne', emoji: '👑', price: 50, plusOnly: false },
  { code: 'rocket', name: 'Fusée', emoji: '🚀', price: 100, plusOnly: false },
  { code: 'planet', name: 'Planète', emoji: '🪐', price: 200, plusOnly: true },
  { code: 'diamond', name: 'Diamant', emoji: '💎', price: 500, plusOnly: false },
];

// Cadeau inconnu du catalogue actuel (retiré depuis) : affichage générique.
export const UNKNOWN_GIFT = { name: 'Cadeau', emoji: '🎁' } as const;

export function findGift(code: string): GiftCatalogItem | null {
  return GIFT_CATALOG.find((gift) => gift.code === code) ?? null;
}

// Nom et emoji d'un cadeau envoyé, même retiré du catalogue depuis (notifications, historiques).
export function giftDisplay(code: string): { name: string; emoji: string } {
  const gift = findGift(code);
  return gift ? { name: gift.name, emoji: gift.emoji } : UNKNOWN_GIFT;
}

// Limite de débit (ADR-050, comme l'ADR-039) : par compte expéditeur. Seuls les cadeaux réellement envoyés comptent
// (un solde insuffisant ne consomme rien).
export const GIFT_RATE_LIMITS: RateLimitRule[] = [
  { limit: 30, windowSeconds: 60 },
  { limit: 500, windowSeconds: 24 * 3600 },
];

export const DEFAULT_GIFTS_PAGE_SIZE = 20;
export const MAX_GIFTS_PAGE_SIZE = 50;
