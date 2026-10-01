import { beforeEach, describe, expect, it } from 'vitest';
import { UsersService } from '../../users/application/users.service';
import type { User } from '../../users/domain/user';
import { InMemoryAccountContentCleanup } from '../../users/infrastructure/in-memory-account-content-cleanup';
import { InMemoryAvatarStorage } from '../../users/infrastructure/in-memory-avatar-storage';
import { InMemoryUserRepository } from '../../users/infrastructure/in-memory-user.repository';
import type { CurrencyEvent } from '../domain/wallet';
import { InMemoryWalletEventPublisher } from '../infrastructure/in-memory-wallet-event-publisher';
import { InMemoryWalletRepository } from '../infrastructure/in-memory-wallet.repository';
import { WalletService } from './wallet.service';
import { InMemorySuspendedAccounts } from '../../../suspension/in-memory-suspended-accounts';

const ALICE = '0192f3a0-0000-7000-8000-00000000000a';
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

let sequence = 0;
const event = (overrides: Partial<CurrencyEvent> = {}): CurrencyEvent => ({
  eventId: `evt-${++sequence}`,
  appUserIds: [ALICE],
  amount: 100,
  source: 'in_app_purchase',
  productId: 'tokens_100',
  storeTransactionId: `tx-${sequence}`,
  store: 'APP_STORE',
  environment: 'SANDBOX',
  occurredAt: new Date('2026-09-27T12:00:00Z'),
  ...overrides,
});

describe('WalletService', () => {
  let wallets: InMemoryWalletRepository;
  let events: InMemoryWalletEventPublisher;
  let service: WalletService;

  function build(rejectSandbox = false) {
    wallets = new InMemoryWalletRepository();
    events = new InMemoryWalletEventPublisher();
    const users = new UsersService(new InMemoryUserRepository([alice]), new InMemoryAvatarStorage(), new InMemoryAccountContentCleanup(), new InMemorySuspendedAccounts());
    service = new WalletService(wallets, users, events, { rejectSandbox });
  }

  beforeEach(() => build());

  it("crédite un achat, une seule fois même si le webhook est rejoué, et pousse le solde", async () => {
    const purchase = event();
    await expect(service.recordCurrencyEvent(purchase)).resolves.toBe('applied');
    await expect(service.recordCurrencyEvent(purchase)).resolves.toBe('duplicate');
    await expect(service.getBalance(ALICE)).resolves.toBe(100);
    expect(events.published).toEqual([{ userId: ALICE, balance: 100 }]);
  });

  it('retire un remboursement sans passer sous 0', async () => {
    await service.recordCurrencyEvent(event({ amount: 100 }));
    await service.recordCurrencyEvent(event({ amount: 50 }));
    await service.recordCurrencyEvent(event({ amount: -100 }));
    await expect(service.getBalance(ALICE)).resolves.toBe(50);
    await service.recordCurrencyEvent(event({ amount: -100 }));
    await expect(service.getBalance(ALICE)).resolves.toBe(0);

    const { items } = await service.listTransactions(ALICE, null, 10);
    expect(items.map((t) => [t.kind, t.amount, t.balanceAfter])).toEqual([
      ['refund', -50, 0],
      ['refund', -100, 50],
      ['purchase', 50, 150],
      ['purchase', 100, 100],
    ]);
    expect(wallets.entries.at(-1)).toMatchObject({ amount: -100, appliedAmount: -50 });
  });

  it("classe un ajustement du tableau de bord RevenueCat", async () => {
    await service.recordCurrencyEvent(event({ source: 'admin_api', amount: 25, productId: null }));
    await expect(service.listTransactions(ALICE, null, 10)).resolves.toMatchObject({ items: [{ kind: 'adjustment', amount: 25 }] });
  });

  it("retrouve le compte parmi les alias (achat commencé en anonyme), sans tenir compte de la casse", async () => {
    await expect(service.recordCurrencyEvent(event({ appUserIds: ['$RCAnonymousID:abc', ALICE.toUpperCase()] }))).resolves.toBe('applied');
    await expect(service.getBalance(ALICE)).resolves.toBe(100);
  });

  it('garde le mouvement d’un client inconnu sans créditer personne', async () => {
    const orphan = event({ appUserIds: ['$RCAnonymousID:abc', '0192f3a0-0000-7000-8000-0000000000ff'] });
    await expect(service.recordCurrencyEvent(orphan)).resolves.toBe('unknownCustomer');
    await expect(service.recordCurrencyEvent(orphan)).resolves.toBe('duplicate');
    expect(wallets.entries).toMatchObject([{ userId: null, appliedAmount: 0, balanceAfter: null, appUserId: '$RCAnonymousID:abc' }]);
    expect(events.published).toEqual([]);
  });

  it('ignore un mouvement nul (autre monnaie), et les achats de test si la sandbox est refusée', async () => {
    await expect(service.recordCurrencyEvent(event({ amount: 0 }))).resolves.toBe('ignored');
    build(true);
    await expect(service.recordCurrencyEvent(event({ environment: 'SANDBOX' }))).resolves.toBe('ignored');
    await expect(service.recordCurrencyEvent(event({ environment: 'PRODUCTION' }))).resolves.toBe('applied');
    await expect(service.getBalance(ALICE)).resolves.toBe(100);
  });

  it("pagine l'historique du plus récent au plus ancien", async () => {
    for (let i = 1; i <= 3; i++) await service.recordCurrencyEvent(event({ amount: i }));
    const first = await service.listTransactions(ALICE, null, 2);
    expect(first.items.map((t) => t.amount)).toEqual([3, 2]);
    const second = await service.listTransactions(ALICE, first.nextCursor, 2);
    expect(second.items.map((t) => t.amount)).toEqual([1]);
    expect(second.nextCursor).toBeNull();
  });

  describe('backoffice', () => {
    const UNKNOWN = '0192f3a0-0000-7000-8000-0000000000ff';

    it('donne les soldes de plusieurs comptes, 0 sans portefeuille', async () => {
      await service.recordCurrencyEvent(event({ amount: 300 }));
      const balances = await service.getBalances([ALICE, UNKNOWN, ALICE]);
      expect([...balances]).toEqual([
        [ALICE, 300],
        [UNKNOWN, 0],
      ]);
    });

    it('liste le journal complet avec les identifiants du store, filtré par compte ou « à rapprocher », page par page', async () => {
      await service.recordCurrencyEvent(event({ amount: 100, environment: 'PRODUCTION' }));
      await service.recordCurrencyEvent(event({ amount: 50, appUserIds: ['$RCAnonymousID:abc'] }));
      await service.recordCurrencyEvent(event({ amount: -150 }));

      const all = await service.listLedger({}, null, 2);
      expect(all.items.map((e) => [e.kind, e.amount, e.appliedAmount, e.balanceAfter, e.unmatched])).toEqual([
        ['refund', -150, -100, 0, false],
        ['purchase', 50, 0, null, true],
      ]);
      expect(all.items[1]).toMatchObject({ userId: null, appUserId: '$RCAnonymousID:abc', storeTransactionId: expect.stringMatching(/^tx-/) });
      const rest = await service.listLedger({}, all.nextCursor, 2);
      expect(rest).toMatchObject({ items: [{ amount: 100, environment: 'PRODUCTION', userId: ALICE }], nextCursor: null });

      expect((await service.listLedger({ userId: ALICE }, null, 10)).items.map((e) => e.amount)).toEqual([-150, 100]);
      expect((await service.listLedger({ unmatched: true }, null, 10)).items.map((e) => e.appUserId)).toEqual(['$RCAnonymousID:abc']);
    });

    it('totalise les jetons vendus, remboursés et ajustés, production et test séparés, clients inconnus compris', async () => {
      const recent = new Date('2026-09-27T12:00:00Z');
      const old = new Date('2026-08-01T12:00:00Z');
      await service.recordCurrencyEvent(event({ amount: 500, environment: 'PRODUCTION', occurredAt: old }));
      await service.recordCurrencyEvent(event({ amount: 100, environment: 'PRODUCTION', occurredAt: recent }));
      await service.recordCurrencyEvent(event({ amount: 200, environment: 'PRODUCTION', appUserIds: ['inconnu'] }));
      await service.recordCurrencyEvent(event({ amount: -100, environment: 'PRODUCTION' }));
      await service.recordCurrencyEvent(event({ amount: 30, environment: 'PRODUCTION', source: 'admin_api' }));
      await service.recordCurrencyEvent(event({ amount: 1000 }));

      await expect(service.getStats(new Date('2026-09-20T00:00:00Z'))).resolves.toEqual({
        production: { purchased: 800, refunded: 100, adjusted: 30 },
        sandbox: { purchased: 1000, refunded: 0, adjusted: 0 },
        purchasedSince: 300,
        inCirculation: 1530,
        unmatched: 1,
      });
    });
  });
});
