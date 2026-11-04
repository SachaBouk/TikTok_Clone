import { type PlusEntitlement, RevenueCatCustomers } from '../domain/revenuecat-customers';

// Adaptateur en mémoire pour les tests : l'état de chaque client chez RevenueCat.
export class InMemoryRevenueCatCustomers extends RevenueCatCustomers {
  readonly entitlements = new Map<string, PlusEntitlement>();
  readonly requests: string[] = [];

  constructor(readonly configured = true) {
    super();
  }

  async fetchPlusEntitlement(appUserId: string): Promise<PlusEntitlement | null> {
    this.requests.push(appUserId);
    return this.entitlements.get(appUserId) ?? null;
  }
}
