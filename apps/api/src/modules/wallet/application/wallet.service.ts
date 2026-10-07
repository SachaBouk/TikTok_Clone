import type { RateLimiter } from '../../../rate-limit/rate-limiter';
import type { InteractionsService } from '../../interactions/application/interactions.service';
import type { NotificationsService } from '../../notifications/application/notifications.service';
import type { UsersService } from '../../users/application/users.service';
import type { User } from '../../users/domain/user';
import type { VideosService } from '../../videos/application/videos.service';
import type { PublishedVideo } from '../../videos/domain/video';
import type { Gift, WalletAmounts } from '../domain/gift';
import { findGift, GIFT_RATE_LIMITS, type GiftCatalogItem, GIFT_CATALOG } from '../domain/gift-catalog';
import {
  CannotGiftYourselfError,
  GiftBlockedError,
  GiftIdConflictError,
  GiftVideoUnavailableError,
  InsufficientBalanceError,
  TooManyGiftsError,
  UnknownGiftError,
} from '../domain/wallet.errors';
import type { CurrencyEvent, LedgerFilter, WalletLedgerEntry, WalletStats, WalletTransaction, WalletTransactionKind } from '../domain/wallet';
import type { WalletEventPublisher } from '../domain/wallet-events';
import type { WalletRepository } from '../domain/wallet.repository';

export interface WalletSettings {
  // Refuser les achats de test (SANDBOX) : à activer en production si TestFlight ne doit rien créditer.
  rejectSandbox: boolean;
}

// Suite donnée à un webhook : appliqué, déjà appliqué, ignoré (mouvement nul, sandbox refusée), ou enregistré
// sans compte (client RevenueCat inconnu de l'API).
export type WebhookOutcome = 'applied' | 'duplicate' | 'ignored' | 'unknownCustomer';

// Historique du portefeuille (ADR-050) : mouvements RevenueCat et cadeaux envoyés, fusionnés par identifiant (UUID v7).
export type WalletHistoryItem = { kind: 'currency'; transaction: WalletTransaction } | { kind: 'giftSent'; gift: Gift; recipient: User | null };

export interface WalletTransactionPage {
  items: WalletHistoryItem[];
  nextCursor: string | null;
}

// Cadeau reçu ou du journal du backoffice, avec ce qu'il faut pour l'afficher (comptes et vidéo nuls : supprimés).
export interface GiftWithContext {
  gift: Gift;
  sender: User | null;
  recipient: User | null;
  video: PublishedVideo | null;
}

export interface GiftPage {
  items: GiftWithContext[];
  nextCursor: string | null;
}

// Cadeau envoyé : le cadeau, et le solde de l'expéditeur après le débit.
export interface SentGift {
  gift: Gift;
  balance: number;
}

// Modules dont dépend la dépense (ADR-003) : vidéo et auteur, masquage et blocages, notification, limite de débit.
export interface GiftDependencies {
  videos: VideosService;
  interactions: InteractionsService;
  notifications: NotificationsService;
  rateLimiter: RateLimiter;
}

export interface WalletLedgerPage {
  items: WalletLedgerEntry[];
  nextCursor: string | null;
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Service applicatif du module wallet (ADR-003, ADR-009). Le solde est crédité par les webhooks RevenueCat (achats,
// remboursements, ajustements) et débité par les cadeaux (ADR-050), qui créditent les gains du destinataire.
export class WalletService {
  constructor(
    private readonly wallets: WalletRepository,
    private readonly users: UsersService,
    private readonly events: WalletEventPublisher,
    private readonly settings: WalletSettings,
    private readonly gifts: GiftDependencies,
  ) {}

  getBalance(userId: string): Promise<number> {
    return this.wallets.getBalance(userId);
  }

  // Solde (jetons achetés) et gains (jetons reçus en cadeaux, ADR-050).
  getAmounts(userId: string): Promise<WalletAmounts> {
    return this.wallets.getAmounts(userId);
  }

  // Historique du compte, du plus récent au plus ancien : mouvements RevenueCat et cadeaux envoyés, fusionnés par
  // identifiant (UUID v7 des deux tables). Curseur : identifiant du dernier élément reçu.
  async listTransactions(userId: string, cursor: string | null, limit: number): Promise<WalletTransactionPage> {
    const [transactions, gifts] = await Promise.all([
      this.wallets.listTransactions(userId, cursor, limit + 1),
      this.wallets.listSentGifts(userId, cursor, limit + 1),
    ]);
    const merged: { id: string; item: WalletHistoryItem | Gift }[] = [
      ...transactions.map((transaction) => ({ id: transaction.id, item: { kind: 'currency' as const, transaction } })),
      ...gifts.map((gift) => ({ id: gift.id, item: gift })),
    ].sort((a, b) => (a.id < b.id ? 1 : a.id > b.id ? -1 : 0));
    const page = merged.slice(0, limit);
    const recipients = await this.usersById(page.flatMap(({ item }) => ('kind' in item ? [] : [item.recipientId])));
    return {
      items: page.map(({ item }) =>
        'kind' in item ? item : { kind: 'giftSent' as const, gift: item, recipient: recipients.get(item.recipientId ?? '') ?? null },
      ),
      nextCursor: merged.length > limit ? page.at(-1)!.id : null,
    };
  }

  // Catalogue des cadeaux (ADR-050), dans le code.
  giftCatalog(): readonly GiftCatalogItem[] {
    return GIFT_CATALOG;
  }

  // Cadeau sur une vidéo publiée (ADR-050). Idempotent par identifiant d'envoi : un renvoi rend le cadeau déjà créé,
  // sans nouveau débit (même identifiant pour une autre vidéo ou un autre cadeau : GiftIdConflictError).
  // Lève UnknownGiftError, GiftVideoUnavailableError (non publiée, supprimée, auteur suspendu), CannotGiftYourselfError,
  // GiftBlockedError, TooManyGiftsError, InsufficientBalanceError.
  async sendGift(senderId: string, videoId: string, giftCode: string, clientGiftId: string): Promise<SentGift> {
    const catalogItem = findGift(giftCode);
    if (!catalogItem) throw new UnknownGiftError(giftCode);
    const [video] = await this.gifts.videos.getPublishedVideos([videoId]);
    if (!video) throw new GiftVideoUnavailableError(videoId);
    const authorId = video.userId;
    if (authorId === senderId) throw new CannotGiftYourselfError();
    // Suspendu : masqué pour tous, invités compris (ADR-037).
    if ((await this.gifts.interactions.getHiddenAccountIds(null)).has(authorId)) throw new GiftVideoUnavailableError(videoId);
    const blocks = await this.gifts.interactions.getBlocks(senderId, [authorId]);
    if (blocks.blockedByMe.has(authorId) || blocks.blockedMe.has(authorId)) throw new GiftBlockedError();

    // Renvoi (réponse perdue) : le cadeau existant, avant la limite de débit, qui ne doit pas le refuser.
    const existing = await this.wallets.findGiftByClientId(senderId, clientGiftId);
    if (existing) return this.alreadySent(existing, videoId, giftCode, senderId);

    const limitKey = `gift:${senderId}`;
    const retryAfter = await this.gifts.rateLimiter.check(limitKey, GIFT_RATE_LIMITS);
    if (retryAfter !== null) throw new TooManyGiftsError(retryAfter);

    const result = await this.wallets.sendGift({
      senderId,
      recipientId: authorId,
      videoId,
      giftCode,
      amount: catalogItem.price,
      clientGiftId,
    });
    if (result.status === 'insufficientBalance') throw new InsufficientBalanceError(result.balance, catalogItem.price);
    if (result.status === 'duplicate') return this.alreadySent(result.gift, videoId, giftCode, senderId);

    // Seuls les cadeaux envoyés comptent dans la limite.
    await this.gifts.rateLimiter.hit(limitKey, GIFT_RATE_LIMITS);
    // Au mieux (ADR-050) : le cadeau est débité, ce qui suit ne doit pas faire échouer la requête.
    const recipientAmounts = await this.wallets.getAmounts(authorId);
    const senderEarned = (await this.wallets.getAmounts(senderId)).earned;
    await this.events.balanceChanged(senderId, { balance: result.senderBalance, earned: senderEarned });
    await this.events.balanceChanged(authorId, recipientAmounts);
    try {
      await this.gifts.notifications.notify({
        type: 'gift',
        actorId: senderId,
        recipientId: authorId,
        videoId,
        giftCode,
        giftAmount: catalogItem.price,
      });
    } catch {
      // Notification perdue : le cadeau reste envoyé et visible dans le portefeuille du créateur.
    }
    return { gift: result.gift, balance: result.senderBalance };
  }

  // Cadeaux reçus par le compte, du plus récent au plus ancien (ADR-050). Curseur : identifiant du dernier reçu.
  async listReceivedGifts(userId: string, cursor: string | null, limit: number): Promise<GiftPage> {
    return this.giftPage(await this.wallets.listReceivedGifts(userId, cursor, limit + 1), limit);
  }

  // Backoffice (ADR-050) : journal des cadeaux, tous ou envoyés et reçus par `userId`, du plus récent au plus ancien.
  async listGifts(filter: { userId?: string }, cursor: string | null, limit: number): Promise<GiftPage> {
    return this.giftPage(await this.wallets.listGifts(filter, cursor, limit + 1), limit);
  }

  // Backoffice : gains de ces comptes (0 sans portefeuille).
  async getEarnings(userIds: string[]): Promise<Map<string, number>> {
    const earnings = await this.wallets.getEarnings([...new Set(userIds)]);
    return new Map(userIds.map((id) => [id, earnings.get(id) ?? 0]));
  }

  // Backoffice (ADR-004) : soldes de ces comptes (0 sans portefeuille).
  async getBalances(userIds: string[]): Promise<Map<string, number>> {
    const balances = await this.wallets.getBalances([...new Set(userIds)]);
    return new Map(userIds.map((id) => [id, balances.get(id) ?? 0]));
  }

  // Backoffice : journal complet (tous comptes, lignes anonymisées et clients inconnus compris), filtré,
  // du plus récent au plus ancien. Curseur : identifiant du dernier mouvement reçu.
  async listLedger(filter: LedgerFilter, cursor: string | null, limit: number): Promise<WalletLedgerPage> {
    const rows = await this.wallets.listLedger(filter, cursor, limit + 1);
    const items = rows.slice(0, limit);
    return { items, nextCursor: rows.length > limit ? items.at(-1)!.id : null };
  }

  // Backoffice : totaux des jetons (production et test séparés), achats en production depuis `since`.
  getStats(since: Date): Promise<WalletStats> {
    return this.wallets.getStats(since);
  }

  // Mouvement de jetons annoncé par RevenueCat. Idempotent : un webhook rejoué n'est appliqué qu'une fois.
  // Le solde à jour est poussé aux appareils du compte.
  async recordCurrencyEvent(event: CurrencyEvent): Promise<WebhookOutcome> {
    if (event.amount === 0) return 'ignored';
    if (this.settings.rejectSandbox && event.environment !== 'PRODUCTION') return 'ignored';

    const userId = await this.resolveCustomer(event.appUserIds);
    const result = await this.wallets.apply({
      eventId: event.eventId,
      userId,
      kind: kindOf(event),
      amount: event.amount,
      appUserId: event.appUserIds[0] ?? '',
      productId: event.productId,
      storeTransactionId: event.storeTransactionId,
      store: event.store,
      environment: event.environment,
      occurredAt: event.occurredAt,
    });
    if (result.status === 'duplicate') return 'duplicate';
    if (!userId || result.balance === null) return 'unknownCustomer';
    await this.events.balanceChanged(userId, { balance: result.balance, earned: result.earned ?? 0 });
    return 'applied';
  }

  // Renvoi d'un cadeau déjà envoyé : le même seulement s'il porte sur la même vidéo et le même cadeau.
  private async alreadySent(gift: Gift, videoId: string, giftCode: string, senderId: string): Promise<SentGift> {
    if (gift.videoId !== videoId || gift.giftCode !== giftCode) throw new GiftIdConflictError();
    return { gift, balance: await this.wallets.getBalance(senderId) };
  }

  private async giftPage(rows: Gift[], limit: number): Promise<GiftPage> {
    const page = rows.slice(0, limit);
    const [users, videos] = await Promise.all([
      this.usersById(page.flatMap((gift) => [gift.senderId, gift.recipientId])),
      this.gifts.videos.getPublishedVideos([...new Set(page.flatMap((gift) => (gift.videoId ? [gift.videoId] : [])))]),
    ]);
    const videoById = new Map(videos.map((video) => [video.id, video]));
    return {
      items: page.map((gift) => ({
        gift,
        sender: users.get(gift.senderId ?? '') ?? null,
        recipient: users.get(gift.recipientId ?? '') ?? null,
        video: videoById.get(gift.videoId ?? '') ?? null,
      })),
      nextCursor: rows.length > limit ? page.at(-1)!.id : null,
    };
  }

  private async usersById(ids: (string | null)[]): Promise<Map<string, User>> {
    const known = [...new Set(ids.filter((id): id is string => id !== null))];
    if (known.length === 0) return new Map();
    return new Map((await this.users.getByIds(known)).map((user) => [user.id, user]));
  }

  // Premier identifiant RevenueCat qui est l'UUID d'un compte existant (l'app s'identifie avec l'UUID du compte ;
  // un achat fait avant l'identification garde l'identifiant anonyme en alias).
  private async resolveCustomer(appUserIds: string[]): Promise<string | null> {
    const candidates = [...new Set(appUserIds.filter((id) => UUID_PATTERN.test(id)).map((id) => id.toLowerCase()))];
    if (candidates.length === 0) return null;
    const existing = new Set((await this.users.getByIds(candidates)).map((user) => user.id));
    return candidates.find((id) => existing.has(id)) ?? null;
  }
}

function kindOf(event: CurrencyEvent): WalletTransactionKind {
  if (event.source === 'admin_api') return 'adjustment';
  return event.amount > 0 ? 'purchase' : 'refund';
}
