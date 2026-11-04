// Abonnement « Plus » (ADR-073) : mensuel ou annuel, acheté par RevenueCat, état tenu par l'API.

export type PlusPeriod = 'monthly' | 'annual';

// `GET /users/me/plus` et événement temps réel `plusChanged`. Abonné : `active` vrai (échéance dans le futur).
export interface PlusStatusDto {
  active: boolean;
  // Absents sans abonnement connu.
  period?: PlusPeriod;
  expiresAt?: string;
  // Faux : renouvellement annulé, actif jusqu'à `expiresAt`.
  willRenew?: boolean;
}
