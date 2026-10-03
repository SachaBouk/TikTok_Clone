import { beforeEach, describe, expect, it } from 'vitest';
import { InMemoryProfileCountersPublisher } from '../../interactions/infrastructure/in-memory-profile-counters-publisher';
import { InteractionsService } from '../../interactions/application/interactions.service';
import { InMemoryInteractionRepository } from '../../interactions/infrastructure/in-memory-interaction.repository';
import { MessagingService } from '../../messaging/application/messaging.service';
import { InMemoryConversationRepository } from '../../messaging/infrastructure/in-memory-conversation.repository';
import { InMemoryMessagingEventPublisher } from '../../messaging/infrastructure/in-memory-messaging-event-publisher';
import { NotificationsService } from '../../notifications/application/notifications.service';
import { InMemoryNotificationPublisher } from '../../notifications/infrastructure/in-memory-notification-publisher';
import { InMemoryNotificationRepository } from '../../notifications/infrastructure/in-memory-notification.repository';
import { UsersService } from '../../users/application/users.service';
import type { User } from '../../users/domain/user';
import { InMemoryAccountContentCleanup } from '../../users/infrastructure/in-memory-account-content-cleanup';
import { InMemoryAvatarStorage } from '../../users/infrastructure/in-memory-avatar-storage';
import { InMemoryUserRepository } from '../../users/infrastructure/in-memory-user.repository';
import { VideosService } from '../../videos/application/videos.service';
import { TranscodingQueue } from '../../videos/domain/transcoding-queue';
import { InMemoryVideoCleanupQueue } from '../../videos/infrastructure/in-memory-video-cleanup-queue';
import { InMemoryVideoEventPublisher } from '../../videos/infrastructure/in-memory-video-event-publisher';
import { InMemoryVideoRepository } from '../../videos/infrastructure/in-memory-video.repository';
import { InMemoryVideoStorage } from '../../videos/infrastructure/in-memory-video-storage';
import type { ReportTarget } from '../domain/report';
import { CannotReportYourselfError, InvalidReportError, ReportTargetNotFoundError, TooManyReportsError } from '../domain/report.errors';
import { InMemoryModerationActionRepository } from '../infrastructure/in-memory-moderation-action.repository';
import { InMemoryReportRepository } from '../infrastructure/in-memory-report.repository';
import { ReportsService } from './reports.service';
import { InMemoryRateLimiter } from '../../../rate-limit/in-memory-rate-limiter';
import { InMemorySuspendedAccounts } from '../../../suspension/in-memory-suspended-accounts';

class NoopTranscodingQueue extends TranscodingQueue {
  async enqueue() {}
  async cancel() {}
}

const user = (id: string): User => ({
  id,
  username: id,
  displayName: id,
  avatarUrl: null,
  bio: null,
  followersCount: 0,
  followingCount: 0,
  createdAt: new Date(),
});

const NOW = new Date('2026-10-01T12:00:00Z');

describe('ReportsService', () => {
  let videoRepository: InMemoryVideoRepository;
  let repository: InMemoryReportRepository;
  let suspended: InMemorySuspendedAccounts;
  let interactions: InteractionsService;
  let messaging: MessagingService;
  let notificationRepository: InMemoryNotificationRepository;
  let actions: InMemoryModerationActionRepository;
  let service: ReportsService;
  let video: string;
  let comment: string;

  async function createVideo(author = 'bob', status: 'ready' | 'processing' = 'ready', description: string | null = 'Ma vidéo') {
    const created = await videoRepository.create({ userId: author, description, rawKey: 'k', uploadId: 'u', rawSize: 1 });
    Object.assign(videoRepository.videos.get(created.id)!, { status, hlsUrl: 'h', thumbnailUrl: 't' });
    return created.id;
  }

  const videoTarget = (id = video): ReportTarget => ({ type: 'video', id });
  // Notifications de modération reçues, résumées : destinataire, type, cible, motif, décision, texte.
  const moderationNotices = () =>
    [...notificationRepository.notifications.values()]
      .filter((n) => n.moderation)
      .map((n) => [n.recipientId, n.type, n.moderation!.targetType, n.moderation!.reason, n.moderation!.outcome, n.moderation!.excerpt]);
  const open = async () =>
    (await service.listOpenTargets(null, 50)).items.map((t) => [
      t.target.type,
      t.target.id,
      t.openCount,
      t.reasons.map((r) => `${r.reason}:${r.count}`).join(','),
    ]);

  beforeEach(async () => {
    videoRepository = new InMemoryVideoRepository();
    const userRepository = new InMemoryUserRepository(['alice', 'bob', 'carol', 'dave'].map(user));
    suspended = new InMemorySuspendedAccounts();
    const users = new UsersService(userRepository, new InMemoryAvatarStorage(), new InMemoryAccountContentCleanup(), suspended);
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
    messaging = new MessagingService(
      new InMemoryConversationRepository(),
      users,
      interactions,
      videos,
      new InMemoryMessagingEventPublisher(),
      new InMemoryRateLimiter(),
    );
    repository = new InMemoryReportRepository(() => NOW);
    actions = new InMemoryModerationActionRepository(() => NOW);
    service = new ReportsService(
      repository,
      actions,
      users,
      videos,
      interactions,
      messaging,
      notifications,
      new InMemoryRateLimiter(),
      suspended,
      () => NOW,
    );
    video = await createVideo();
    comment = (await interactions.addComment('carol', video, 'Commentaire de Carol')).comment.id;
  });

  describe('signaler', () => {
    it('une vidéo, un commentaire, un compte : compte visé et texte copiés, précision nettoyée', async () => {
      await service.report('alice', { target: videoTarget(), reason: 'spam', details: '  Lien suspect  ' });
      await service.report('alice', { target: { type: 'comment', id: comment }, reason: 'harassment' });
      await service.report('alice', { target: { type: 'account', id: 'dave' }, reason: 'impersonation', details: '   ' });

      expect(repository.reports.map((r) => [r.target.type, r.targetUserId, r.excerpt, r.details])).toEqual([
        ['video', 'bob', 'Ma vidéo', 'Lien suspect'],
        ['comment', 'carol', 'Commentaire de Carol', null],
        ['account', 'dave', null, null],
      ]);
    });

    it('un seul signalement ouvert par personne et par cible ; le doublon ne compte pas dans la limite', async () => {
      await service.report('alice', { target: videoTarget(), reason: 'spam' });
      await service.report('alice', { target: videoTarget(), reason: 'hate' });
      expect(repository.reports).toHaveLength(1);
      await service.report('carol', { target: videoTarget(), reason: 'spam' });
      await expect(open()).resolves.toEqual([['video', video, 2, 'spam:2']]);
    });

    it('refuse son propre contenu ou son compte, et ce qui est invisible', async () => {
      await expect(service.report('bob', { target: videoTarget(), reason: 'spam' })).rejects.toBeInstanceOf(CannotReportYourselfError);
      await expect(service.report('carol', { target: { type: 'comment', id: comment }, reason: 'spam' })).rejects.toBeInstanceOf(
        CannotReportYourselfError,
      );
      await expect(service.report('alice', { target: { type: 'account', id: 'alice' }, reason: 'spam' })).rejects.toBeInstanceOf(
        CannotReportYourselfError,
      );

      const unpublished = await createVideo('bob', 'processing');
      for (const target of [
        videoTarget(unpublished),
        videoTarget('inconnue'),
        { type: 'comment', id: 'inconnu' },
        { type: 'account', id: 'inconnu' },
      ] as ReportTarget[]) {
        await expect(service.report('alice', { target, reason: 'spam' })).rejects.toBeInstanceOf(ReportTargetNotFoundError);
      }
      // Compte suspendu (ADR-037) : ni lui ni ses contenus ne sont visibles.
      await suspended.add('bob');
      await expect(service.report('alice', { target: videoTarget(), reason: 'spam' })).rejects.toBeInstanceOf(ReportTargetNotFoundError);
      await expect(service.report('alice', { target: { type: 'account', id: 'bob' }, reason: 'spam' })).rejects.toBeInstanceOf(
        ReportTargetNotFoundError,
      );
      expect(repository.reports).toEqual([]);
    });

    it('refuse une précision de plus de 500 caractères', async () => {
      await expect(service.report('alice', { target: videoTarget(), reason: 'other', details: 'x'.repeat(501) })).rejects.toBeInstanceOf(
        InvalidReportError,
      );
    });

    it('10 signalements par heure, puis 429 avec le délai', async () => {
      const videos = await Promise.all(Array.from({ length: 11 }, () => createVideo()));
      for (const id of videos.slice(0, 10)) await service.report('alice', { target: videoTarget(id), reason: 'spam' });
      const error = await service.report('alice', { target: videoTarget(videos[10]), reason: 'spam' }).catch((e: unknown) => e);
      expect(error).toBeInstanceOf(TooManyReportsError);
      expect((error as TooManyReportsError).retryAfterSeconds).toBeGreaterThan(0);
    });
  });

  describe('file de modération', () => {
    it('groupe par cible, de la plus récemment signalée à la plus ancienne, motifs du plus fréquent au moins fréquent', async () => {
      await service.report('alice', { target: videoTarget(), reason: 'spam' });
      await service.report('dave', { target: { type: 'comment', id: comment }, reason: 'hate' });
      await service.report('carol', { target: videoTarget(), reason: 'violence' });
      await service.report('dave', { target: videoTarget(), reason: 'violence' });

      await expect(open()).resolves.toEqual([
        ['video', video, 3, 'violence:2,spam:1'],
        ['comment', comment, 1, 'hate:1'],
      ]);
      const first = await service.listOpenTargets(null, 1);
      expect(first.items.map((t) => t.target.id)).toEqual([video]);
      await expect(service.listOpenTargets(first.nextCursor, 1)).resolves.toMatchObject({ items: [{ target: { id: comment } }], nextCursor: null });
      await expect(service.countOpenTargets()).resolves.toBe(2);
    });

    it('sans suite : la cible quitte la file, son historique reste, et on peut la signaler de nouveau', async () => {
      await service.report('alice', { target: videoTarget(), reason: 'spam' });
      await expect(service.dismiss(videoTarget(), 'admin')).resolves.toBe(1);
      await expect(open()).resolves.toEqual([]);

      await service.report('alice', { target: videoTarget(), reason: 'spam' });
      const detail = await service.getTarget(videoTarget());
      expect(detail.open?.openCount).toBe(1);
      expect(detail.reports.map((r) => [r.resolution, r.resolvedBy])).toEqual([
        [null, null],
        ['dismissed', 'admin'],
      ]);
      await expect(service.getTarget(videoTarget('jamais-signalee'))).rejects.toBeInstanceOf(ReportTargetNotFoundError);
    });

    it('contenu supprimé : la cible seule ; compte suspendu : toutes les cibles du compte', async () => {
      const other = await createVideo();
      await service.report('alice', { target: videoTarget(), reason: 'spam' });
      await service.report('alice', { target: videoTarget(other), reason: 'spam' });
      await service.report('alice', { target: { type: 'account', id: 'bob' }, reason: 'spam' });
      await service.report('alice', { target: { type: 'comment', id: comment }, reason: 'spam' });

      let removed = false;
      await service.removeContent({ adminId: 'dave', target: videoTarget(), authorId: 'bob', excerpt: 'Ma vidéo', reason: 'spam' }, async () => {
        removed = true;
      });
      expect(removed).toBe(true);
      await service.accountSuspended('bob', 'dave', 'Spam répété');
      await expect(open()).resolves.toEqual([['comment', comment, 1, 'spam:1']]);
      expect(repository.reports.map((r) => r.resolution)).toEqual(['contentRemoved', 'accountSuspended', 'accountSuspended', null]);
    });
  });

  describe('messages', () => {
    let message: string;

    beforeEach(async () => {
      await interactions.setFollow('alice', 'bob', true);
      await interactions.setFollow('bob', 'alice', true);
      const { conversation } = await messaging.openConversation('bob', 'alice');
      message = (await messaging.sendMessage('bob', conversation.id, { content: 'Message de Bob' })).message.id;
    });

    it('un message reçu : expéditeur visé, seul ce message copié ; ni le sien, ni hors de la conversation', async () => {
      await service.report('alice', { target: { type: 'message', id: message }, reason: 'harassment' });
      expect(repository.reports.map((r) => [r.target.type, r.targetUserId, r.targetUsername, r.excerpt])).toEqual([
        ['message', 'bob', 'bob', 'Message de Bob'],
      ]);
      await expect(service.report('bob', { target: { type: 'message', id: message }, reason: 'spam' })).rejects.toBeInstanceOf(
        CannotReportYourselfError,
      );
      await expect(service.report('carol', { target: { type: 'message', id: message }, reason: 'spam' })).rejects.toBeInstanceOf(
        ReportTargetNotFoundError,
      );
    });

    it('message retiré : expéditeur prévenu avec le motif, signalement clos, journal', async () => {
      await service.report('alice', { target: { type: 'message', id: message }, reason: 'harassment' });
      await service.removeContent(
        { adminId: 'dave', target: { type: 'message', id: message }, authorId: 'bob', excerpt: 'Message de Bob', reason: 'harassment' },
        () => messaging.removeMessage(message).then(() => undefined),
      );
      await expect(messaging.getMessages([message])).resolves.toEqual([]);
      expect(moderationNotices()).toEqual([
        ['bob', 'contentRemoved', 'message', 'harassment', null, 'Message de Bob'],
        ['alice', 'reportResolved', 'message', null, 'contentRemoved', 'Message de Bob'],
      ]);
      expect(actions.actions.map((a) => [a.action, a.adminUsername, a.targetUsername, a.reason, a.reportsClosed])).toEqual([
        ['messageRemoved', 'dave', 'bob', 'harassment', 1],
      ]);
    });
  });

  describe('décisions annoncées et journal (ADR-038)', () => {
    it('sans suite : les personnes qui ont signalé sont prévenues, une fois chacune ; journalisé', async () => {
      await service.report('alice', { target: videoTarget(), reason: 'spam' });
      await service.report('carol', { target: videoTarget(), reason: 'hate' });
      await expect(service.dismiss(videoTarget(), 'dave')).resolves.toBe(2);
      expect(moderationNotices()).toEqual([
        ['alice', 'reportResolved', 'video', null, 'dismissed', 'Ma vidéo'],
        ['carol', 'reportResolved', 'video', null, 'dismissed', 'Ma vidéo'],
      ]);
      expect(actions.actions.map((a) => [a.action, a.target.id, a.targetUsername, a.reportsClosed])).toEqual([['reportsDismissed', video, 'bob', 2]]);
      // Plus rien d'ouvert : ni annonce ni journal.
      await expect(service.dismiss(videoTarget(), 'dave')).resolves.toBe(0);
      expect(actions.actions).toHaveLength(1);
    });

    it('suppression qui échoue : signalements clos, mais rien n’est annoncé ni journalisé', async () => {
      await service.report('alice', { target: videoTarget(), reason: 'spam' });
      const failure = new Error('stockage indisponible');
      await expect(
        service.removeContent({ adminId: 'dave', target: videoTarget(), authorId: 'bob', excerpt: 'Ma vidéo', reason: 'spam' }, async () => {
          throw failure;
        }),
      ).rejects.toBe(failure);
      expect(moderationNotices()).toEqual([]);
      expect(actions.actions).toEqual([]);
    });

    it('suspension : une annonce par personne et par cible ; suspension et levée journalisées, filtrables par compte', async () => {
      await service.report('alice', { target: videoTarget(), reason: 'spam' });
      await service.report('alice', { target: { type: 'account', id: 'bob' }, reason: 'spam' });
      await service.accountSuspended('bob', 'dave', 'Spam répété');
      await service.suspensionLifted('bob', 'dave');
      await service.dismiss({ type: 'comment', id: comment }, 'dave');

      expect(moderationNotices().map(([to, , type, , outcome]) => [to, type, outcome])).toEqual([
        ['alice', 'video', 'accountSuspended'],
        ['alice', 'account', 'accountSuspended'],
      ]);
      const page = await service.listActions({ targetUserId: 'bob' }, null, 10);
      expect(page.items.map((a) => [a.action, a.note, a.reportsClosed])).toEqual([
        ['suspensionLifted', null, 0],
        ['accountSuspended', 'Spam répété', 2],
      ]);
      expect((await service.listActions({}, null, 1)).nextCursor).not.toBeNull();
    });
  });
});
