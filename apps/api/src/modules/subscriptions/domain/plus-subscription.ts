// Abonnement « Plus » (ADR-073) : mensuel ou annuel, acheté par RevenueCat. L'API garde le dernier état connu, relu
// chez RevenueCat à chaque webhook d'abonnement (les webhooks peuvent arriver en double ou dans le désordre).

export type PlusPeriod = 'monthly' | 'annual';

export interface PlusSubscription {
  userId: string;
  productId: string;
  period: PlusPeriod;
  // Échéance, période de grâce comprise : abonné tant qu'elle est dans le futur.
  expiresAt: Date;
  // Faux : renouvellement annulé (actif jusqu'à l'échéance).
  willRenew: boolean;
  store: string | null;
  // SANDBOX (achats de test, Test Store compris) ou PRODUCTION.
  environment: string;
}

export interface PlusStatus {
  active: boolean;
  // Dernier abonnement connu (null : jamais abonné).
  subscription: PlusSubscription | null;
}

// Entitlement de RevenueCat accordée par les deux produits.
export const PLUS_ENTITLEMENT = 'plus';
export const PLUS_ANNUAL_PRODUCT = 'plus_annual';

// Événements du webhook qui peuvent changer l'abonnement : ils déclenchent une relecture de l'état chez RevenueCat.
export const SUBSCRIPTION_EVENT_TYPES: readonly string[] = [
  'INITIAL_PURCHASE',
  'RENEWAL',
  'PRODUCT_CHANGE',
  'CANCELLATION',
  'UNCANCELLATION',
  'EXPIRATION',
  'BILLING_ISSUE',
  'SUBSCRIPTION_EXTENDED',
  'TEMPORARY_ENTITLEMENT_GRANT',
  'TRANSFER',
];

export function periodOf(productId: string): PlusPeriod {
  return productId === PLUS_ANNUAL_PRODUCT ? 'annual' : 'monthly';
}

export function isActive(subscription: PlusSubscription | null, now: Date): boolean {
  return subscription !== null && subscription.expiresAt > now;
}
