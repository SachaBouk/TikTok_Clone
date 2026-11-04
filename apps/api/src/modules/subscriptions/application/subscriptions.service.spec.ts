import { beforeEach, describe, expect, it } from 'vitest';
import { InMemoryPlusMembers } from '../../../plus/in-memory-plus-members';
import { InMemorySuspendedAccounts } from '../../../suspension/in-memory-suspended-accounts';
import { UsersService } from '../../users/application/users.service';
import type { User } from '../../users/domain/user';
import { InMemoryAccountContentCleanup } from '../../users/infrastructure/in-memory-account-content-cleanup';
import { InMemoryAvatarStorage } from '../../users/infrastructure/in-memory-avatar-storage';
import { InMemoryInterestRepository } from '../../users/infrastructure/in-memory-interest.repository';
import { InMemoryReceivedLikesCounter } from '../../users/infrastructure/in-memory-received-likes-counter';
import { InMemoryUserRepository } from '../../users/infrastructure/in-memory-user.repository';
import { SubscriptionsNotConfiguredError } from '../domain/subscription.errors';
import { parsePlusEntitlement } from '../infrastructure/http-revenuecat-customers';
import { InMemoryPlusEventPublisher } from '../infrastructure/in-memory-plus-event-publisher';
import { InMemoryPlusSubscriptionRepository } from '../infrastructure/in-memory-plus-subscription.repository';
import { InMemoryRevenueCatCustomers } from '../infrastructure/in-memory-revenuecat-customers';
import { SubscriptionsService } from './subscriptions.service';

const ALICE = '0192f3a0-0000-7000-8000-000000000001';
const NOW = new Date('2026-11-08T12:00:00Z');
const IN_A_MONTH = new Date('2026-12-08T12:00:00Z');

const alice: User = {
  id: ALICE,
  username: 'alice',
  displayName: 'Alice',
  avatarUrl: null,
  bio: null,
  followersCount: 0,
  followingCount: 0,
  createdAt: new Date('2026-01-01T00:00:00Z'),
};

describe('SubscriptionsService (ADR-073)', () => {
  let repository: InMemoryPlusSubscriptionRepository;
  let customers: InMemoryRevenueCatCustomers;
  let plus: InMemoryPlusMembers;
  let events: InMemoryPlusEventPublisher;
  let clock: Date;
  let service: SubscriptionsService;

  function build(rejectSandbox = false, configured = true) {
    repository = new InMemoryPlusSubscriptionRepository();
    customers = new InMemoryRevenueCatCustomers(configured);
    plus = new InMemoryPlusMembers();
    events = new InMemoryPlusEventPublisher();
    const users = new UsersService(
      new InMemoryUserRepository([{ ...alice }]),
      new InMemoryAvatarStorage(),
      new InMemoryAccountContentCleanup(),
      new InMemoryInterestRepository(),
      new InMemorySuspendedAccounts(),
      new InMemoryReceivedLikesCounter(),
    );
    service = new SubscriptionsService(repository, customers, users, plus, events, { rejectSandbox }, () => clock);
  }

  beforeEach(() => {
    clock = NOW;
    build();
  });

  it('souscription : état relu chez RevenueCat, enregistré, registre écrit, appareils prévenus', async () => {
    customers.entitlements.set(ALICE, { productId: 'plus_annual', expiresAt: IN_A_MONTH, willRenew: true, store: 'app_store', sandbox: false });
    await expect(service.refresh(['$RCAnonymousID:abc', ALICE.toUpperCase()])).resolves.toBe('updated');
    expect(customers.requests).toEqual([ALICE]);
    expect(repository.rows.get(ALICE)).toMatchObject({ period: 'annual', environment: 'PRODUCTION', expiresAt: IN_A_MONTH });
    await expect(plus.isActive(ALICE, NOW)).resolves.toBe(true);
    expect(events.published).toEqual([{ userId: ALICE, status: { active: true, subscription: expect.objectContaining({ period: 'annual' }) } }]);
    await expect(service.getStatus(ALICE)).resolves.toMatchObject({ active: true });
  });

  it('webhook rejoué ou dans le désordre : même état, puisqu’il est relu', async () => {
    customers.entitlements.set(ALICE, { productId: 'plus_monthly', expiresAt: IN_A_MONTH, willRenew: false, store: 'test_store', sandbox: true });
    await service.refresh([ALICE]);
    await service.refresh([ALICE]);
    expect(repository.rows.get(ALICE)).toMatchObject({ period: 'monthly', willRenew: false, environment: 'SANDBOX' });
  });

  it('échéance passée : plus abonné ; entitlement retirée (remboursement) : fin immédiate', async () => {
    customers.entitlements.set(ALICE, { productId: 'plus_monthly', expiresAt: IN_A_MONTH, willRenew: true, store: 'app_store', sandbox: false });
    await service.refresh([ALICE]);
    clock = new Date(IN_A_MONTH.getTime() + 1);
    await expect(service.getStatus(ALICE)).resolves.toMatchObject({ active: false });

    clock = NOW;
    customers.entitlements.delete(ALICE);
    await expect(service.refresh([ALICE])).resolves.toBe('updated');
    expect(repository.rows.get(ALICE)?.expiresAt).toEqual(NOW);
    await expect(plus.isActive(ALICE, new Date(NOW.getTime() + 1))).resolves.toBe(false);
  });

  it('ignore un client sans abonnement, inconnu, ou un achat de test si la sandbox est refusée', async () => {
    await expect(service.refresh([ALICE])).resolves.toBe('ignored');
    await expect(service.refresh(['0192f3a0-0000-7000-8000-0000000000ff', 'pas-un-uuid'])).resolves.toBe('unknownCustomer');
    build(true);
    customers.entitlements.set(ALICE, { productId: 'plus_monthly', expiresAt: IN_A_MONTH, willRenew: true, store: 'test_store', sandbox: true });
    await expect(service.refresh([ALICE])).resolves.toBe('ignored');
    expect(repository.rows.size).toBe(0);
  });

  it('sans clé secrète : erreur (webhook en 503, RevenueCat le renvoie)', async () => {
    build(false, false);
    await expect(service.refresh([ALICE])).rejects.toBeInstanceOf(SubscriptionsNotConfiguredError);
  });

  it('reconstruit le registre avec les seuls abonnements en cours', async () => {
    await repository.save({
      userId: ALICE,
      productId: 'plus_monthly',
      period: 'monthly',
      expiresAt: IN_A_MONTH,
      willRenew: true,
      store: null,
      environment: 'PRODUCTION',
    });
    await repository.save({ ...(await repository.find(ALICE))!, userId: 'ancien', expiresAt: new Date(NOW.getTime() - 1) });
    await plus.set('fantome', IN_A_MONTH);
    await expect(service.syncRegistry()).resolves.toBe(1);
    await expect(plus.activeAmong([ALICE, 'ancien', 'fantome'], NOW)).resolves.toEqual(new Set([ALICE]));
  });
});

describe('parsePlusEntitlement (réponse de RevenueCat)', () => {
  it('échéance (période de grâce comprise), produit, store, annulation et sandbox', () => {
    const body = {
      subscriber: {
        entitlements: {
          plus: { product_identifier: 'plus_monthly', expires_date: '2026-12-08T12:00:00Z', grace_period_expires_date: '2026-12-24T12:00:00Z' },
        },
        subscriptions: {
          plus_monthly: { store: 'test_store', is_sandbox: false, unsubscribe_detected_at: '2026-11-10T08:00:00Z' },
        },
      },
    };
    expect(parsePlusEntitlement(body)).toEqual({
      productId: 'plus_monthly',
      expiresAt: new Date('2026-12-24T12:00:00Z'),
      willRenew: false,
      store: 'test_store',
      sandbox: true,
    });
  });

  it('pas d’entitlement « plus » : null', () => {
    expect(parsePlusEntitlement({ subscriber: { entitlements: {}, subscriptions: {} } })).toBeNull();
    expect(parsePlusEntitlement({})).toBeNull();
  });
});
