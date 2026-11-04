// Lecture de l'état d'un client chez RevenueCat (ADR-073), côté serveur, avec la clé secrète.
export interface PlusEntitlement {
  productId: string;
  // Échéance, période de grâce comprise.
  expiresAt: Date;
  willRenew: boolean;
  store: string | null;
  // Achat de test (sandbox, Test Store).
  sandbox: boolean;
}

export abstract class RevenueCatCustomers {
  // Vrai si la clé secrète est configurée : sans elle, les webhooks d'abonnement ne peuvent pas être traités.
  abstract readonly configured: boolean;
  // Entitlement « plus » du client, ou null s'il ne l'a jamais eue (ou plus du tout : remboursement). Lève une erreur
  // si RevenueCat ne répond pas : le webhook répond 500 et RevenueCat le renvoie.
  abstract fetchPlusEntitlement(appUserId: string): Promise<PlusEntitlement | null>;
}
