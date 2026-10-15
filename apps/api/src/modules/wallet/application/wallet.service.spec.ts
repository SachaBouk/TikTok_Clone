import { beforeEach, describe, expect, it } from 'vitest';
import { InMemoryRateLimiter } from '../../../rate-limit/in-memory-rate-limiter';
import { InteractionsService } from '../../interactions/application/interactions.service';
import { InMemoryInteractionRepository } from '../../interactions/infrastructure/in-memory-interaction.repository';
import { InMemoryProfileCountersPublisher } from '../../interactions/infrastructure/in-memory-profile-counters-publisher';
import { NotificationsService } from '../../notifications/application/notifications.service';
import { InMemoryNotificationPublisher } from '../../notifications/infrastructure/in-memory-notification-publisher';
import { InMemoryNotificationRepository } from '../../notifications/infrastructure/in-memory-notification.repository';
import { VideosService } from '../../videos/application/videos.service';
import { TranscodingQueue } from '../../videos/domain/transcoding-queue';
import { InMemoryVideoCleanupQueue } from '../../videos/infrastructure/in-memory-video-cleanup-queue';
import { InMemoryVideoEventPublisher } from '../../videos/infrastructure/in-memory-video-event-publisher';
import { InMemoryVideoRepository } from '../../videos/infrastructure/in-memory-video.repository';
import { InMemoryVideoStorage } from '../../videos/infrastructure/in-memory-video-storage';
import {
  CannotGiftYourselfError,
  GiftBlockedError,
  GiftIdConflictError,
  GiftLiveUnavailableError,
  GiftVideoUnavailableError,
  InsufficientBalanceError,
  TooManyGiftsError,
  UnknownGiftError,
} from '../domain/wallet.errors';
import { UsersService } from '../../users/application/users.service';
import type { User } from '../../users/domain/user';
import { InMemoryAccountContentCleanup } from '../../users/infrastructure/in-memory-account-content-cleanup';
import { InMemoryInterestRepository } from '../../users/infrastructure/in-memory-interest.repository';
import { InMemoryAvatarStorage } from '../../users/infrastructure/in-memory-avatar-storage';
import { InMemoryUserRepository } from '../../users/infrastructure/in-memory-user.repository';
import type { CurrencyEvent } from '../domain/wallet';
import { InMemoryWalletEventPublisher } from '../infrastructure/in-memory-wallet-event-publisher';
import { InMemoryWalletRepository } from '../infrastructure/in-memory-wallet.repository';
import { WalletService, type WalletHistoryItem } from './wallet.service';
import { InMemorySuspendedAccounts } from '../../../suspension/in-memory-suspended-accounts';
import { inMemoryLive } from '../../live/infrastructure/in-memory-live';
import { InMemoryReceivedLikesCounter } from '../../users/infrastructure/in-memory-received-likes-counter';

const ALICE = '0192f3a0-0000-7000-8000-00000000000a';
const BOB = '0192f3a0-0000-7000-8000-00000000000b';
const CAROL = '0192f3a0-0000-7000-8000-00000000000c';
const account = (id: string, username: string): User => ({
  id,
  username,
  displayName: username.charAt(0).toUpperCase() + username.slice(1),
  avatarUrl: null,
  bio: null,
  followersCount: 0,
  followingCount: 0,
  createdAt: new Date('2026-01-01T00:00:00Z'),
});
const alice = account(ALICE, 'alice');

class NoopTranscodingQueue extends TranscodingQueue {
  async enqueue() {}
  async cancel() {}
}

// Mouvement de l'historique, à plat : sorte, montant, solde après.
const line = (item: WalletHistoryItem) =>
  item.kind === 'currency'
    ? [item.transaction.kind, item.transaction.amount, item.transaction.balanceAfter]
    : ['giftSent', -item.gift.amount, item.gift.senderBalanceAfter];

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
  let videoRepository: InMemoryVideoRepository;
  let interactions: InteractionsService;
  let notificationRepository: InMemoryNotificationRepository;
  let suspended: InMemorySuspendedAccounts;
  let rateLimiter: InMemoryRateLimiter;
  let lives: ReturnType<typeof inMemoryLive>;

  function build(rejectSandbox = false) {
    wallets = new InMemoryWalletRepository();
    events = new InMemoryWalletEventPublisher();
    suspended = new InMemorySuspendedAccounts();
    const userRepository = new InMemoryUserRepository([alice, account(BOB, 'bob'), account(CAROL, 'carol')]);
    const users = new UsersService(
      userRepository,
      new InMemoryAvatarStorage(),
      new InMemoryAccountContentCleanup(),
      new InMemoryInterestRepository(),
      suspended,
      new InMemoryReceivedLikesCounter(),
    );
    let tick = 0;
    videoRepository = new InMemoryVideoRepository(() => new Date(Date.UTC(2026, 0, 1) + ++tick * 1000));
    const videos = new VideosService(
      videoRepository,
      new InMemoryVideoStorage(),
      new NoopTranscodingQueue(),
      new InMemoryVideoEventPublisher(),
      new InMemoryVideoCleanupQueue(),
      new InMemoryRateLimiter(),
    );
    notificationRepository = new InMemoryNotificationRepository();
    const notifications = new NotificationsService(notificationRepository, users, videos, new InMemoryNotificationPublisher(), suspended);
    interactions = new InteractionsService(
      new InMemoryInteractionRepository(videoRepository, userRepository),
      videos,
      users,
      notifications,
      new InMemoryRateLimiter(),
      suspended,
      new InMemoryProfileCountersPublisher(),
    );
    rateLimiter = new InMemoryRateLimiter();
    lives = inMemoryLive(users, interactions, notifications);
    service = new WalletService(
      wallets,
      users,
      events,
      { rejectSandbox },
      { videos, lives: lives.service, interactions, notifications, rateLimiter },
    );
  }

  // Vidéo publiée de `userId`.
  async function publish(userId = BOB, status: 'ready' | 'processing' = 'ready') {
    const video = await videoRepository.create({ userId, description: null, rawKey: 'k', uploadId: 'u', rawSize: 1 });
    Object.assign(videoRepository.videos.get(video.id)!, { status, hlsUrl: `https://cdn/${video.id}/master.m3u8`, thumbnailUrl: 't' });
    return video.id;
  }

  let clientIds = 0;
  const clientId = () => `0192f3a0-0000-7000-9000-${String(++clientIds).padStart(12, '0')}`;

  beforeEach(() => build());

  it('crédite un achat, une seule fois même si le webhook est rejoué, et pousse le solde', async () => {
    const purchase = event();
    await expect(service.recordCurrencyEvent(purchase)).resolves.toBe('applied');
    await expect(service.recordCurrencyEvent(purchase)).resolves.toBe('duplicate');
    await expect(service.getBalance(ALICE)).resolves.toBe(100);
    expect(events.published).toEqual([{ userId: ALICE, balance: 100, earned: 0 }]);
  });

  it('retire un remboursement sans passer sous 0', async () => {
    await service.recordCurrencyEvent(event({ amount: 100 }));
    await service.recordCurrencyEvent(event({ amount: 50 }));
    await service.recordCurrencyEvent(event({ amount: -100 }));
    await expect(service.getBalance(ALICE)).resolves.toBe(50);
    await service.recordCurrencyEvent(event({ amount: -100 }));
    await expect(service.getBalance(ALICE)).resolves.toBe(0);

    const { items } = await service.listTransactions(ALICE, null, 10);
    expect(items.map(line)).toEqual([
      ['refund', -50, 0],
      ['refund', -100, 50],
      ['purchase', 50, 150],
      ['purchase', 100, 100],
    ]);
    expect(wallets.entries.at(-1)).toMatchObject({ amount: -100, appliedAmount: -50 });
  });

  it('classe un ajustement du tableau de bord RevenueCat', async () => {
    await service.recordCurrencyEvent(event({ source: 'admin_api', amount: 25, productId: null }));
    await expect(service.listTransactions(ALICE, null, 10)).resolves.toMatchObject({ items: [{ transaction: { kind: 'adjustment', amount: 25 } }] });
  });

  it('retrouve le compte parmi les alias (achat commencé en anonyme), sans tenir compte de la casse', async () => {
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
    expect(first.items.map((t) => line(t)[1])).toEqual([3, 2]);
    const second = await service.listTransactions(ALICE, first.nextCursor, 2);
    expect(second.items.map((t) => line(t)[1])).toEqual([1]);
    expect(second.nextCursor).toBeNull();
  });

  describe('cadeaux (ADR-050)', () => {
    beforeEach(async () => {
      await service.recordCurrencyEvent(event({ amount: 100 }));
      events.published.length = 0;
    });

    it('débite l’expéditeur, crédite les gains du créateur, notifie et pousse les deux portefeuilles', async () => {
      const video = await publish(BOB);
      const sent = await service.sendGift(ALICE, video, 'heart', clientId());
      expect(sent).toMatchObject({
        balance: 95,
        gift: { senderId: ALICE, recipientId: BOB, videoId: video, giftCode: 'heart', amount: 5, senderBalanceAfter: 95 },
      });
      await expect(service.getAmounts(ALICE)).resolves.toEqual({ balance: 95, earned: 0 });
      await expect(service.getAmounts(BOB)).resolves.toEqual({ balance: 0, earned: 5 });
      expect(events.published).toEqual([
        { userId: ALICE, balance: 95, earned: 0 },
        { userId: BOB, balance: 0, earned: 5 },
      ]);
      expect([...notificationRepository.notifications.values()]).toMatchObject([
        { type: 'gift', actorId: ALICE, recipientId: BOB, videoId: video, gift: { code: 'heart', amount: 5 } },
      ]);
    });

    it('un renvoi avec le même identifiant rend le même cadeau, sans nouveau débit ; autre vidéo : conflit', async () => {
      const video = await publish(BOB);
      const other = await publish(BOB);
      const id = clientId();
      const first = await service.sendGift(ALICE, video, 'star', id);
      const again = await service.sendGift(ALICE, video, 'star', id);
      expect(again.gift.id).toBe(first.gift.id);
      expect(again.balance).toBe(90);
      expect(wallets.gifts).toHaveLength(1);
      await expect(service.sendGift(ALICE, other, 'star', id)).rejects.toBeInstanceOf(GiftIdConflictError);
      await expect(service.sendGift(ALICE, video, 'rose', id)).rejects.toBeInstanceOf(GiftIdConflictError);
    });

    it('refuse un solde insuffisant sans rien débiter ni compter dans la limite', async () => {
      const video = await publish(BOB);
      const refused = await service.sendGift(ALICE, video, 'diamond', clientId()).catch((e: unknown) => e);
      expect(refused).toBeInstanceOf(InsufficientBalanceError);
      expect((refused as InsufficientBalanceError).message).toBe('Solde insuffisant : 100 jetons, il en faut 500');
      await expect(service.getAmounts(ALICE)).resolves.toEqual({ balance: 100, earned: 0 });
      await expect(service.getAmounts(BOB)).resolves.toEqual({ balance: 0, earned: 0 });
      expect(wallets.gifts).toHaveLength(0);
      expect(notificationRepository.notifications.size).toBe(0);
      // Rien n'a été compté : 30 cadeaux passent encore dans la minute.
      for (let i = 0; i < 30; i++) await service.sendGift(ALICE, video, 'rose', clientId());
    });

    it('refuse un cadeau inconnu, sa propre vidéo, une vidéo non publiée, d’un compte suspendu ou bloqué', async () => {
      const video = await publish(BOB);
      await expect(service.sendGift(ALICE, video, 'licorne', clientId())).rejects.toBeInstanceOf(UnknownGiftError);
      await expect(service.sendGift(BOB, video, 'rose', clientId())).rejects.toBeInstanceOf(CannotGiftYourselfError);
      await expect(service.sendGift(ALICE, await publish(BOB, 'processing'), 'rose', clientId())).rejects.toBeInstanceOf(GiftVideoUnavailableError);
      await expect(service.sendGift(ALICE, '0192f3a0-0000-7000-8000-0000000000ee', 'rose', clientId())).rejects.toBeInstanceOf(
        GiftVideoUnavailableError,
      );
      await suspended.add(BOB);
      await expect(service.sendGift(ALICE, video, 'rose', clientId())).rejects.toBeInstanceOf(GiftVideoUnavailableError);
      await suspended.remove(BOB);
      await interactions.setBlock(BOB, 'alice', true);
      await expect(service.sendGift(ALICE, video, 'rose', clientId())).rejects.toBeInstanceOf(GiftBlockedError);
      await interactions.setBlock(BOB, 'alice', false);
      await interactions.setBlock(ALICE, 'bob', true);
      await expect(service.sendGift(ALICE, video, 'rose', clientId())).rejects.toBeInstanceOf(GiftBlockedError);
      expect(wallets.gifts).toHaveLength(0);
    });

    it('pendant un live (ADR-053) : même dépense vers son auteur, annoncé dans la salle, sans notification', async () => {
      const { item } = await lives.service.start(BOB, {});
      const id = clientId();
      const sent = await service.sendLiveGift(ALICE, item.live.id, 'crown', id);
      expect(sent).toMatchObject({ balance: 50, gift: { recipientId: BOB, videoId: null, liveId: item.live.id, amount: 50 } });
      await expect(service.getAmounts(BOB)).resolves.toEqual({ balance: 0, earned: 50 });
      expect(lives.room.events.filter((e) => e.type === 'gift')).toMatchObject([{ sender: ALICE, code: 'crown', giftsAmount: 50 }]);
      expect(notificationRepository.notifications.size).toBe(0);
      // Renvoi : le même cadeau ; même identifiant sur une vidéo : conflit.
      await expect(service.sendLiveGift(ALICE, item.live.id, 'crown', id)).resolves.toMatchObject({ gift: { id: sent.gift.id } });
      await expect(service.sendGift(ALICE, await publish(BOB), 'crown', id)).rejects.toBeInstanceOf(GiftIdConflictError);
      expect(lives.room.events.filter((e) => e.type === 'gift')).toHaveLength(1);
      // Son propre live, un live terminé ou inconnu.
      await expect(service.sendLiveGift(BOB, item.live.id, 'rose', clientId())).rejects.toBeInstanceOf(CannotGiftYourselfError);
      await lives.service.stop(BOB, item.live.id);
      await expect(service.sendLiveGift(ALICE, item.live.id, 'rose', clientId())).rejects.toBeInstanceOf(GiftLiveUnavailableError);
      await expect(service.sendLiveGift(ALICE, '0192f3a0-0000-7000-8000-0000000000ee', 'rose', clientId())).rejects.toBeInstanceOf(
        GiftLiveUnavailableError,
      );
    });

    it('limite à 30 cadeaux par minute', async () => {
      const video = await publish(BOB);
      for (let i = 0; i < 30; i++) await service.sendGift(ALICE, video, 'rose', clientId());
      const refused = await service.sendGift(ALICE, video, 'rose', clientId()).catch((e: unknown) => e);
      expect(refused).toBeInstanceOf(TooManyGiftsError);
      expect((refused as TooManyGiftsError).retryAfterSeconds).toBeGreaterThan(0);
      await expect(service.getBalance(ALICE)).resolves.toBe(70);
    });

    it('historique : achats et cadeaux envoyés fusionnés du plus récent au plus ancien, avec le destinataire', async () => {
      const video = await publish(BOB);
      await service.sendGift(ALICE, video, 'heart', clientId());
      await service.recordCurrencyEvent(event({ amount: 10 }));
      await service.sendGift(ALICE, video, 'rose', clientId());
      const first = await service.listTransactions(ALICE, null, 2);
      expect(first.items.map(line)).toEqual([
        ['giftSent', -1, 104],
        ['purchase', 10, 105],
      ]);
      expect(first.items[0]).toMatchObject({ kind: 'giftSent', recipient: { username: 'bob' } });
      const second = await service.listTransactions(ALICE, first.nextCursor, 2);
      expect(second.items.map(line)).toEqual([
        ['giftSent', -5, 95],
        ['purchase', 100, 100],
      ]);
      expect(second.nextCursor).toBeNull();
    });

    it('cadeaux reçus et journal du backoffice, avec expéditeur et vidéo ; comptes et vidéos supprimés anonymisés', async () => {
      const video = await publish(BOB);
      await service.sendGift(ALICE, video, 'crown', clientId());
      await service.recordCurrencyEvent(event({ amount: 10, appUserIds: [CAROL] }));
      await service.sendGift(CAROL, video, 'star', clientId());
      const received = await service.listReceivedGifts(BOB, null, 10);
      expect(received.items.map((r) => [r.sender?.username, r.gift.giftCode, r.video?.id])).toEqual([
        ['carol', 'star', video],
        ['alice', 'crown', video],
      ]);
      await expect(service.listGifts({ userId: CAROL }, null, 10)).resolves.toMatchObject({ items: [{ gift: { giftCode: 'star' } }] });
      await expect(service.listGifts({}, null, 1)).resolves.toMatchObject({
        items: [{ gift: { giftCode: 'star' } }],
        nextCursor: expect.any(String),
      });

      wallets.forget(ALICE);
      wallets.forget(video);
      const after = await service.listReceivedGifts(BOB, null, 10);
      expect(after.items[1]).toMatchObject({ sender: null, video: null, gift: { giftCode: 'crown', amount: 50 } });

      const stats = await service.getStats(new Date('2000-01-01'));
      expect(stats.gifts).toEqual({ spent: 60, spentSince: 60, earned: 60 });
      expect([...(await service.getEarnings([BOB, ALICE]))]).toEqual([
        [BOB, 60],
        [ALICE, 0],
      ]);
    });

    it('catalogue du moins cher au plus cher', () => {
      const prices = service.giftCatalog().map((gift) => gift.price);
      expect(prices).toEqual([...prices].sort((a, b) => a - b));
      expect(service.giftCatalog()[0]).toEqual({ code: 'rose', name: 'Rose', emoji: '🌹', price: 1 });
    });
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
        gifts: { spent: 0, spentSince: 0, earned: 0 },
      });
    });
  });
});
