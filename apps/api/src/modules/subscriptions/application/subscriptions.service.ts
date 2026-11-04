import type { PlusMembers } from '../../../plus/plus-members';
import type { UsersService } from '../../users/application/users.service';
import type { PlusEventPublisher } from '../domain/plus-events';
import { isActive, periodOf, type PlusStatus, type PlusSubscription } from '../domain/plus-subscription';
import type { PlusSubscriptionRepository } from '../domain/plus-subscription.repository';
import type { RevenueCatCustomers } from '../domain/revenuecat-customers';
import { SubscriptionsNotConfiguredError } from '../domain/subscription.errors';

export interface SubscriptionSettings {
  // Refuser les achats de test (sandbox, Test Store), comme pour les jetons (ADR-009).
  rejectSandbox: boolean;
}

// Suite donnée à un webhook d'abonnement : état enregistré, ignoré (achat de test refusé, client sans abonnement), ou
// client inconnu de l'API.
export type SubscriptionOutcome = 'updated' | 'ignored' | 'unknownCustomer';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Service applicatif du module subscriptions (ADR-003, ADR-073) : état de l'abonnement « Plus », tenu par l'API. La
// base fait foi ; le registre partagé `PlusMembers` en garde l'échéance pour les modules qui donnent les avantages.
export class SubscriptionsService {
  constructor(
    private readonly subscriptions: PlusSubscriptionRepository,
    private readonly customers: RevenueCatCustomers,
    private readonly users: UsersService,
    private readonly plus: PlusMembers,
    private readonly events: PlusEventPublisher,
    private readonly settings: SubscriptionSettings,
    private readonly now: () => Date = () => new Date(),
  ) {}

  async getStatus(userId: string): Promise<PlusStatus> {
    return this.statusOf(await this.subscriptions.find(userId));
  }

  // Webhook d'abonnement reçu : l'état n'est pas lu dans l'événement mais relu chez RevenueCat, ce qui rend le traitement
  // idempotent et insensible à l'ordre d'arrivée. Le registre est écrit, et l'état poussé aux appareils du compte.
  async refresh(appUserIds: string[]): Promise<SubscriptionOutcome> {
    if (!this.customers.configured) throw new SubscriptionsNotConfiguredError();
    const userId = await this.resolveCustomer(appUserIds);
    if (!userId) return 'unknownCustomer';

    const entitlement = await this.customers.fetchPlusEntitlement(userId);
    const previous = await this.subscriptions.find(userId);
    let subscription: PlusSubscription;
    if (entitlement) {
      const environment = entitlement.sandbox ? 'SANDBOX' : 'PRODUCTION';
      if (this.settings.rejectSandbox && environment !== 'PRODUCTION') return 'ignored';
      subscription = {
        userId,
        productId: entitlement.productId,
        period: periodOf(entitlement.productId),
        expiresAt: entitlement.expiresAt,
        willRenew: entitlement.willRenew,
        store: entitlement.store,
        environment,
      };
    } else if (previous) {
      // Entitlement retirée (remboursement, révocation) : l'abonnement prend fin maintenant.
      const now = this.now();
      subscription = { ...previous, expiresAt: previous.expiresAt < now ? previous.expiresAt : now, willRenew: false };
    } else {
      return 'ignored';
    }

    if (!(await this.subscriptions.save(subscription))) return 'unknownCustomer';
    await this.plus.set(userId, subscription.expiresAt);
    // Au mieux : l'app relit l'état à sa reconnexion.
    await this.events.plusChanged(userId, this.statusOf(subscription)).catch(() => undefined);
    return 'updated';
  }

  // Reconstruit le registre depuis la base (démarrage de l'API) ; renvoie le nombre d'abonnés.
  async syncRegistry(): Promise<number> {
    const active = await this.subscriptions.listActive(this.now());
    await this.plus.replaceAll(active.map((s) => ({ userId: s.userId, expiresAt: s.expiresAt })));
    return active.length;
  }

  private statusOf(subscription: PlusSubscription | null): PlusStatus {
    return { active: isActive(subscription, this.now()), subscription };
  }

  // Le premier identifiant RevenueCat qui est l'UUID d'un compte existant (l'app s'identifie avec l'UUID du compte).
  private async resolveCustomer(appUserIds: string[]): Promise<string | null> {
    const candidates = [...new Set(appUserIds.filter((id) => UUID_PATTERN.test(id)).map((id) => id.toLowerCase()))];
    if (candidates.length === 0) return null;
    const existing = new Set((await this.users.getByIds(candidates)).map((user) => user.id));
    return candidates.find((id) => existing.has(id)) ?? null;
  }
}
