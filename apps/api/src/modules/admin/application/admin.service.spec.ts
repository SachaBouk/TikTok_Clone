import { beforeEach, describe, expect, it } from 'vitest';
import { AuthService } from '../../auth/application/auth.service';
import { AccessTokenIssuer } from '../../auth/domain/access-token-issuer';
import { AppleIdentityVerifier } from '../../auth/domain/apple-identity-verifier';
import { PasswordHasher } from '../../auth/domain/password-hasher';
import { InMemoryAuthAccountRepository } from '../../auth/infrastructure/in-memory-auth-account.repository';
import { InMemoryRefreshTokenRepository } from '../../auth/infrastructure/in-memory-refresh-token.repository';
import { InteractionsService } from '../../interactions/application/interactions.service';
import { InMemoryInteractionRepository } from '../../interactions/infrastructure/in-memory-interaction.repository';
import { NotificationsService } from '../../notifications/application/notifications.service';
import { RealtimeService } from '../../realtime/application/realtime.service';
import { ReportsService } from '../../reports/application/reports.service';
import { InMemoryReportRepository } from '../../reports/infrastructure/in-memory-report.repository';
import { AccessTokenVerifier } from '../../realtime/domain/access-token-verifier';
import { InMemoryRealtimeBus } from '../../realtime/infrastructure/in-memory-realtime-bus';
import { InMemoryNotificationPublisher } from '../../notifications/infrastructure/in-memory-notification-publisher';
import { InMemoryNotificationRepository } from '../../notifications/infrastructure/in-memory-notification.repository';
import { UsersService } from '../../users/application/users.service';
import type { User } from '../../users/domain/user';
import { InMemoryAccountContentCleanup } from '../../users/infrastructure/in-memory-account-content-cleanup';
import { InMemoryAvatarStorage } from '../../users/infrastructure/in-memory-avatar-storage';
import { InMemoryUserRepository } from '../../users/infrastructure/in-memory-user.repository';
import { VideosService } from '../../videos/application/videos.service';
import { TranscodingQueue } from '../../videos/domain/transcoding-queue';
import type { VideoStatus } from '../../videos/domain/video';
import { InMemoryVideoCleanupQueue } from '../../videos/infrastructure/in-memory-video-cleanup-queue';
import { InMemoryVideoEventPublisher } from '../../videos/infrastructure/in-memory-video-event-publisher';
import { InMemoryVideoRepository } from '../../videos/infrastructure/in-memory-video.repository';
import { InMemoryVideoStorage } from '../../videos/infrastructure/in-memory-video-storage';
import { WalletService } from '../../wallet/application/wallet.service';
import type { CurrencyEvent } from '../../wallet/domain/wallet';
import { InMemoryWalletEventPublisher } from '../../wallet/infrastructure/in-memory-wallet-event-publisher';
import { InMemoryWalletRepository } from '../../wallet/infrastructure/in-memory-wallet.repository';
import { AdminActionRefusedError, AdminTargetNotFoundError } from '../domain/admin.errors';
import { AdminService } from './admin.service';
import { InMemoryRateLimiter } from '../../../rate-limit/in-memory-rate-limiter';
import { InMemorySuspendedAccounts } from '../../../suspension/in-memory-suspended-accounts';

// Registre des comptes suspendus (ADR-037), partagé par les services d'un même test.
let suspended = new InMemorySuspendedAccounts();

class NoopTranscodingQueue extends TranscodingQueue {
  async enqueue() {}
  async cancel() {}
}

// AuthService ne sert ici qu'au rôle : les autres ports ne sont jamais appelés.
class UnusedHasher extends PasswordHasher {
  async hash(): Promise<string> {
    throw new Error('inutilisé');
  }
  async verify(): Promise<boolean> {
    throw new Error('inutilisé');
  }
}
class UnusedIssuer extends AccessTokenIssuer {
  async issue(): Promise<string> {
    throw new Error('inutilisé');
  }
  async verify() {
    return null;
  }
}
class UnusedApple extends AppleIdentityVerifier {
  async verify(): Promise<never> {
    throw new Error('inutilisé');
  }
}

const NOW = new Date('2026-09-27T12:00:00Z');
// Identifiants UUID v7 croissants : ordre de création, comme en base.
const ALICE = '0192f3a0-0000-7000-8000-000000000001';
const BOB = '0192f3a0-0000-7000-8000-000000000002';
const CAROL = '0192f3a0-0000-7000-8000-000000000003';

const user = (id: string, username: string, createdAt: Date): User => ({
  id,
  username,
  displayName: username.toUpperCase(),
  avatarUrl: null,
  bio: null,
  followersCount: 0,
  followingCount: 0,
  createdAt,
});

describe('AdminService', () => {
  let userRepository: InMemoryUserRepository;
  let videoRepository: InMemoryVideoRepository;
  let accounts: InMemoryAuthAccountRepository;
  let cleanup: InMemoryVideoCleanupQueue;
  let interactions: InteractionsService;
  let wallet: WalletService;
  let service: AdminService;
  let bus: InMemoryRealtimeBus;
  let refreshTokens: InMemoryRefreshTokenRepository;
  let reports: ReportsService;
  let reportRepository: InMemoryReportRepository;

  let eventSequence = 0;
  const tokens = (appUserId: string, amount: number, environment = 'PRODUCTION'): CurrencyEvent => ({
    eventId: `evt-${++eventSequence}`,
    appUserIds: [appUserId],
    amount,
    source: 'in_app_purchase',
    productId: `tokens_${Math.abs(amount)}`,
    storeTransactionId: `tx-${eventSequence}`,
    store: 'APP_STORE',
    environment,
    occurredAt: NOW,
  });

  async function createVideo(userId: string, status: VideoStatus = 'ready') {
    const created = await videoRepository.create({ userId, description: 'Démo', rawKey: `${userId}/k`, uploadId: 'u', rawSize: 1 });
    Object.assign(videoRepository.videos.get(created.id)!, { status, hlsUrl: 'h', thumbnailUrl: 't' });
    return created.id;
  }

  beforeEach(() => {
    userRepository = new InMemoryUserRepository([
      user(ALICE, 'alice', new Date('2026-01-01T00:00:00Z')),
      user(BOB, 'bob', new Date('2026-09-25T00:00:00Z')),
      user(CAROL, 'carol', new Date('2026-09-26T00:00:00Z')),
    ]);
    videoRepository = new InMemoryVideoRepository(() => NOW);
    accounts = new InMemoryAuthAccountRepository();
    // Les comptes existent aussi côté auth (même table `users`, colonnes propres à chaque module).
    for (const [id, username] of [[ALICE, 'alice'], [BOB, 'bob'], [CAROL, 'carol']]) {
      accounts.accounts.push({ id: id!, email: `${username}@test.local`, passwordHash: null, appleSub: null, username: username!, displayName: username! });
    }
    refreshTokens = new InMemoryRefreshTokenRepository();
    bus = new InMemoryRealtimeBus();
    cleanup = new InMemoryVideoCleanupQueue();
    suspended = new InMemorySuspendedAccounts();
    const users = new UsersService(userRepository, new InMemoryAvatarStorage(), new InMemoryAccountContentCleanup(), suspended, () => NOW);
    const videos = new VideosService(videoRepository, new InMemoryVideoStorage(), new NoopTranscodingQueue(), new InMemoryVideoEventPublisher(), cleanup, () => NOW);
    const notifications = new NotificationsService(new InMemoryNotificationRepository(), users, videos, new InMemoryNotificationPublisher(), suspended);
    interactions = new InteractionsService(new InMemoryInteractionRepository(videoRepository, userRepository), videos, users, notifications, new InMemoryRateLimiter(), suspended);
    const auth = new AuthService(
      accounts,
      refreshTokens,
      new UnusedHasher(),
      new UnusedIssuer(),
      new UnusedApple(),
      { accessTokenTtlSeconds: 900, refreshTokenTtlDays: 30 },
      new InMemoryRateLimiter(),
      suspended,
      () => NOW,
    );
    wallet = new WalletService(new InMemoryWalletRepository(), users, new InMemoryWalletEventPublisher(), { rejectSandbox: false });
    const realtime = new RealtimeService(bus, new (class extends AccessTokenVerifier {
      async verify() {
        return null;
      }
    })());
    reportRepository = new InMemoryReportRepository(() => NOW);
    reports = new ReportsService(reportRepository, users, videos, interactions, new InMemoryRateLimiter(), suspended, () => NOW);
    service = new AdminService(users, videos, interactions, auth, wallet, realtime, reports, () => NOW);
  });

  describe('signalements (ADR-038)', () => {
    it('file : cibles décrites (miniature, vidéo commentée, compte visé, disponibilité) ; détail avec les comptes', async () => {
      const video = await createVideo(BOB);
      const { comment } = await interactions.addComment(CAROL, video, 'Spam');
      await reports.report(ALICE, { target: { type: 'video', id: video }, reason: 'spam' });
      await reports.report(ALICE, { target: { type: 'comment', id: comment.id }, reason: 'hate', details: 'Insultes' });
      await reports.report(BOB, { target: { type: 'account', id: CAROL }, reason: 'harassment' });

      const page = await service.listReportTargets(null, 10);
      expect(page.items.map((i) => [i.target.type, i.targetUser.id, i.available, i.thumbnailUrl, i.videoId, i.excerpt, i.open?.openCount])).toEqual([
        ['account', CAROL, true, null, null, null, 1],
        ['comment', CAROL, true, null, video, 'Spam', 1],
        ['video', BOB, true, 't', null, 'Démo', 1],
      ]);

      const detail = await service.getReportTarget({ type: 'comment', id: comment.id });
      expect(detail.reports.map((r) => [r.reporter?.id, r.report.details, r.resolvedBy])).toEqual([[ALICE, 'Insultes', null]]);
      expect((await service.getStats()).reports.openTargets).toBe(3);
    });

    it('supprimer le contenu ou suspendre le compte clôt les signalements ; sans suite sinon', async () => {
      accounts.adminIds.add(CAROL);
      const video = await createVideo(BOB);
      const { comment } = await interactions.addComment(ALICE, video, 'Spam');
      await reports.report(CAROL, { target: { type: 'video', id: video }, reason: 'spam' });
      await reports.report(CAROL, { target: { type: 'comment', id: comment.id }, reason: 'spam' });
      await reports.report(CAROL, { target: { type: 'account', id: ALICE }, reason: 'spam' });

      await service.removeVideo(CAROL, video);
      const removed = await service.getReportTarget({ type: 'video', id: video });
      expect(removed.target).toMatchObject({ available: false, open: null });
      expect(removed.reports.map((r) => [r.report.resolution, r.resolvedBy?.id])).toEqual([['contentRemoved', CAROL]]);

      await service.dismissReports(CAROL, { type: 'account', id: ALICE });
      await expect(service.dismissReports(CAROL, { type: 'account', id: ALICE })).rejects.toBeInstanceOf(AdminTargetNotFoundError);
      // Commentaire supprimé par son auteur : sa cible reste dans la file, « indisponible ».
      await interactions.deleteComment(ALICE, comment.id);
      expect((await service.listReportTargets(null, 10)).items.map((i) => [i.target.type, i.available])).toEqual([['comment', false]]);
      await service.suspendAccount(CAROL, ALICE, 'Spam');
      expect((await service.listReportTargets(null, 10)).items).toEqual([]);
      await expect(service.getReportTarget({ type: 'video', id: 'jamais' })).rejects.toBeInstanceOf(AdminTargetNotFoundError);
    });
  });

  describe('suspension (ADR-037)', () => {
    it('suspend un compte : fiche à jour, connexions fermées, statistiques ; la levée efface tout', async () => {
      accounts.adminIds.add(CAROL);
      const account = await service.suspendAccount(CAROL, BOB, '  Spam répété ');
      expect(account.suspension).toEqual({ suspendedAt: NOW, reason: 'Spam répété', suspendedBy: expect.objectContaining({ id: CAROL }) });
      expect(bus.published).toEqual([{ userId: BOB, disconnect: true }]);
      await expect(suspended.has(BOB)).resolves.toBe(true);
      expect((await service.getStats()).users.suspended).toBe(1);
      expect((await service.listAccounts(null, null, 10)).items.find((a) => a.user.id === BOB)?.suspension).not.toBeNull();

      await expect(service.liftSuspension(BOB)).resolves.toMatchObject({ suspension: null });
      await expect(suspended.has(BOB)).resolves.toBe(false);
      expect((await service.getStats()).users.suspended).toBe(0);
    });

    it("refuse un administrateur ou soi-même (409) ; compte inconnu (404) ; rien n'est fermé", async () => {
      accounts.adminIds.add(CAROL);
      accounts.adminIds.add(ALICE);
      await expect(service.suspendAccount(CAROL, ALICE, 'Motif')).rejects.toBeInstanceOf(AdminActionRefusedError);
      await expect(service.suspendAccount(CAROL, CAROL, 'Motif')).rejects.toBeInstanceOf(AdminActionRefusedError);
      await expect(service.suspendAccount(CAROL, '0192f3a0-0000-7000-8000-0000000000ff', 'Motif')).rejects.toBeInstanceOf(AdminTargetNotFoundError);
      await expect(service.liftSuspension('0192f3a0-0000-7000-8000-0000000000ff')).rejects.toBeInstanceOf(AdminTargetNotFoundError);
      expect(bus.published).toEqual([]);
    });
  });

  describe('comptes', () => {
    it('liste les comptes par pages, avec leur rôle et leur nombre de vidéos', async () => {
      accounts.adminIds.add(CAROL);
      await createVideo(BOB);
      await createVideo(BOB, 'failed');

      const first = await service.listAccounts(null, null, 2);
      expect(first.items.map(({ user, isAdmin, videosCount }) => [user.username, isAdmin, videosCount])).toEqual([
        ['carol', true, 0],
        ['bob', false, 2],
      ]);
      expect(first.nextCursor).toBe(BOB);

      const second = await service.listAccounts(null, first.nextCursor, 2);
      expect(second.items.map((item) => item.user.username)).toEqual(['alice']);
      expect(second.nextCursor).toBeNull();
    });

    it('cherche un compte, et en ouvre un par identifiant', async () => {
      await expect(service.listAccounts('@BO', null, 10)).resolves.toMatchObject({ items: [{ user: { id: BOB } }], nextCursor: null });
      await expect(service.getAccount(ALICE)).resolves.toMatchObject({ user: { username: 'alice' }, isAdmin: false, videosCount: 0, tokenBalance: 0 });
      await expect(service.getAccount('0192f3a0-0000-7000-8000-00000000dead')).rejects.toBeInstanceOf(AdminTargetNotFoundError);
    });
  });

  describe('vidéos', () => {
    it('liste les vidéos de tous statuts avec leur auteur, filtrées', async () => {
      const ready = await createVideo(ALICE);
      const failed = await createVideo(BOB, 'failed');

      const all = await service.listVideos({}, null, 10);
      expect(all.items.map(({ video, author }) => [video.id, author.username]).sort()).toEqual(
        [
          [ready, 'alice'],
          [failed, 'bob'],
        ].sort(),
      );
      await expect(service.listVideos({ status: 'failed' }, null, 10)).resolves.toMatchObject({ items: [{ video: { id: failed } }] });
      await expect(service.listVideos({ userId: ALICE }, null, 10)).resolves.toMatchObject({ items: [{ video: { id: ready } }] });
    });

    it("saute une vidéo dont l'auteur a disparu, sans décaler la pagination", async () => {
      await createVideo(ALICE);
      await createVideo(ALICE);
      await userRepository.delete(ALICE);
      const page = await service.listVideos({}, null, 1);
      expect(page.items).toEqual([]);
      expect(page.nextCursor).not.toBeNull();
    });

    it('ouvre et retire une vidéo, quel que soit son auteur', async () => {
      const video = await createVideo(CAROL, 'processing');
      await expect(service.getVideo(video)).resolves.toMatchObject({ video: { status: 'processing' }, author: { id: CAROL } });

      await service.removeVideo(CAROL, video);
      expect(videoRepository.videos.has(video)).toBe(false);
      expect(cleanup.scheduled).toHaveLength(1);
      await expect(service.removeVideo(CAROL, video)).rejects.toBeInstanceOf(AdminTargetNotFoundError);
      await expect(service.getVideo(video)).rejects.toBeInstanceOf(AdminTargetNotFoundError);
    });
  });

  describe('commentaires', () => {
    it('liste les commentaires avec leur auteur et leur vidéo, puis en retire un', async () => {
      const video = await createVideo(ALICE);
      const first = await interactions.addComment(BOB, video, 'Bravo');
      const second = await interactions.addComment(CAROL, video, 'Spam');

      const page = await service.listComments({ videoId: video }, null, 1);
      expect(page.items.map(({ comment, author, video }) => [comment.content, author.username, video.userId])).toEqual([['Spam', 'carol', ALICE]]);
      expect(page.nextCursor).toBe(second.comment.id);
      await expect(service.listComments({ userId: BOB }, null, 10)).resolves.toMatchObject({ items: [{ comment: { id: first.comment.id } }] });

      await service.removeComment(CAROL, second.comment.id);
      await expect(service.listComments({}, null, 10)).resolves.toMatchObject({ items: [{ comment: { id: first.comment.id } }] });
      await expect(service.removeComment(CAROL, second.comment.id)).rejects.toBeInstanceOf(AdminTargetNotFoundError);
    });
  });

  // Comptes du 25 et du 26 septembre, vidéos datées de NOW ; le commentaire est daté par l'horloge réelle.
  it('résume la plateforme : totaux et nouveautés des 7 derniers jours', async () => {
    const video = await createVideo(ALICE);
    await createVideo(BOB, 'failed');
    await createVideo(BOB, 'uploading');
    await interactions.addComment(BOB, video, 'Bravo');

    await expect(service.getStats()).resolves.toEqual({
      reports: { openTargets: 0 },
      users: { total: 3, last7Days: 2, suspended: 0 },
      videos: { total: 3, last7Days: 3, uploading: 1, processing: 0, ready: 1, failed: 1 },
      comments: { total: 1, last7Days: 1 },
      tokens: {
        production: { purchased: 0, refunded: 0, adjusted: 0 },
        sandbox: { purchased: 0, refunded: 0, adjusted: 0 },
        purchasedSince: 0,
        inCirculation: 0,
        unmatched: 0,
      },
    });
  });

  describe('jetons', () => {
    it('donne le solde de chaque compte et les totaux du tableau de bord', async () => {
      await wallet.recordCurrencyEvent(tokens(BOB, 500));
      await wallet.recordCurrencyEvent(tokens(BOB, -200));
      await wallet.recordCurrencyEvent(tokens(CAROL, 100, 'SANDBOX'));
      await wallet.recordCurrencyEvent(tokens('$RCAnonymousID:x', 300));

      const page = await service.listAccounts(null, null, 10);
      expect(page.items.map(({ user, tokenBalance }) => [user.username, tokenBalance])).toEqual([
        ['carol', 100],
        ['bob', 300],
        ['alice', 0],
      ]);
      await expect(service.getStats()).resolves.toMatchObject({
        tokens: {
          production: { purchased: 800, refunded: 200, adjusted: 0 },
          sandbox: { purchased: 100, refunded: 0, adjusted: 0 },
          purchasedSince: 800,
          inCirculation: 400,
          unmatched: 1,
        },
      });
    });

    it('liste le journal avec le compte crédité, filtré par compte ou « à rapprocher »', async () => {
      await wallet.recordCurrencyEvent(tokens(BOB, 500));
      await wallet.recordCurrencyEvent(tokens('$RCAnonymousID:x', 300));
      await wallet.recordCurrencyEvent(tokens(CAROL, 100));

      const first = await service.listWalletTransactions({}, null, 2);
      expect(first.items.map(({ entry, user }) => [entry.amount, user?.username ?? null, entry.unmatched])).toEqual([
        [100, 'carol', false],
        [300, null, true],
      ]);
      const rest = await service.listWalletTransactions({}, first.nextCursor, 2);
      expect(rest).toMatchObject({ items: [{ entry: { amount: 500 }, user: { username: 'bob' } }], nextCursor: null });
      await expect(service.listWalletTransactions({ userId: BOB }, null, 10)).resolves.toMatchObject({ items: [{ entry: { amount: 500 } }] });
      await expect(service.listWalletTransactions({ unmatched: true }, null, 10)).resolves.toMatchObject({
        items: [{ entry: { appUserId: '$RCAnonymousID:x' }, user: null }],
      });
    });

    it('ligne d’un compte supprimé depuis : anonyme, sans être « à rapprocher »', async () => {
      await wallet.recordCurrencyEvent(tokens(BOB, 500));
      await userRepository.delete(BOB);
      const { items } = await service.listWalletTransactions({}, null, 10);
      // L'adaptateur en mémoire ne reproduit pas le SET NULL de la base : le compte, introuvable, est absent.
      expect(items).toMatchObject([{ entry: { unmatched: false, balanceAfter: 500 }, user: null }]);
    });
  });
});
