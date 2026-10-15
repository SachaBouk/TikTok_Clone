import { beforeEach, describe, expect, it, vi } from 'vitest';
import { InMemoryRateLimiter } from '../../../rate-limit/in-memory-rate-limiter';
import { InMemorySuspendedAccounts } from '../../../suspension/in-memory-suspended-accounts';
import { InteractionsService } from '../../interactions/application/interactions.service';
import { InMemoryInteractionRepository } from '../../interactions/infrastructure/in-memory-interaction.repository';
import { InMemoryProfileCountersPublisher } from '../../interactions/infrastructure/in-memory-profile-counters-publisher';
import { NotificationsService } from '../../notifications/application/notifications.service';
import { InMemoryNotificationPublisher } from '../../notifications/infrastructure/in-memory-notification-publisher';
import { InMemoryNotificationRepository } from '../../notifications/infrastructure/in-memory-notification.repository';
import { UsersService } from '../../users/application/users.service';
import type { User } from '../../users/domain/user';
import { InMemoryAccountContentCleanup } from '../../users/infrastructure/in-memory-account-content-cleanup';
import { InMemoryInterestRepository } from '../../users/infrastructure/in-memory-interest.repository';
import { InMemoryAvatarStorage } from '../../users/infrastructure/in-memory-avatar-storage';
import { InMemoryUserRepository } from '../../users/infrastructure/in-memory-user.repository';
import { VideosService } from '../../videos/application/videos.service';
import { TranscodingQueue } from '../../videos/domain/transcoding-queue';
import { InMemoryVideoCleanupQueue } from '../../videos/infrastructure/in-memory-video-cleanup-queue';
import { InMemoryVideoEventPublisher } from '../../videos/infrastructure/in-memory-video-event-publisher';
import { InMemoryVideoRepository } from '../../videos/infrastructure/in-memory-video.repository';
import { InMemoryVideoStorage } from '../../videos/infrastructure/in-memory-video-storage';
import { HOST_FIRST_CONNECT_GRACE_MS, HOST_RECONNECT_GRACE_MS, LIVE_MAX_DURATION_MS, MAX_LIVE_MESSAGE_LENGTH } from '../domain/live';
import {
  InvalidHeartsCountError,
  InvalidLiveMessageError,
  InvalidLiveTitleError,
  LiveEndedError,
  LiveMediaUnavailableError,
  LiveMessageForbiddenError,
  LiveNotFoundError,
  OwnLiveError,
  TooManyLiveActionsError,
} from '../domain/live.errors';
import { inMemoryLive } from '../infrastructure/in-memory-live';
import { InMemoryReceivedLikesCounter } from '../../users/infrastructure/in-memory-received-likes-counter';

class NoopTranscodingQueue extends TranscodingQueue {
  async enqueue() {}
  async cancel() {}
}

const user = (id: string): User => ({
  id,
  username: id,
  displayName: id.toUpperCase(),
  avatarUrl: null,
  bio: null,
  followersCount: 0,
  followingCount: 0,
  createdAt: new Date('2026-01-01T00:00:00Z'),
});

describe('LiveService (ADR-053)', () => {
  let clock: Date;
  let suspended: InMemorySuspendedAccounts;
  let interactions: InteractionsService;
  let users: UsersService;
  let notificationRepository: InMemoryNotificationRepository;
  let live: ReturnType<typeof inMemoryLive>;

  const advance = (ms: number) => (clock = new Date(clock.getTime() + ms));
  const roomEvents = (type: string) => live.room.events.filter((event) => event.type === type);

  beforeEach(() => {
    clock = new Date('2026-10-09T10:00:00Z');
    suspended = new InMemorySuspendedAccounts();
    const userRepository = new InMemoryUserRepository(['alice', 'bob', 'carol', 'dave', 'erin'].map(user));
    const videoRepository = new InMemoryVideoRepository();
    users = new UsersService(
      userRepository,
      new InMemoryAvatarStorage(),
      new InMemoryAccountContentCleanup(),
      new InMemoryInterestRepository(),
      suspended,
      new InMemoryReceivedLikesCounter(),
    );
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
    live = inMemoryLive(users, interactions, notifications, () => clock);
  });

  describe('lancement et fin', () => {
    it('ouvre la salle, donne un jeton pour publier, programme la fin et la vérification, prévient les abonnés', async () => {
      await interactions.setFollow('bob', 'alice', true);
      await interactions.setFollow('carol', 'alice', true);
      const connection = await live.service.start('alice', { title: '  Bonjour  ' });

      expect(connection.role).toBe('host');
      expect(connection.item.live).toMatchObject({ userId: 'alice', title: 'Bonjour', status: 'live' });
      expect(connection.item.stats).toMatchObject({ durationSeconds: 0, viewersCount: 0 });
      expect(connection.token).toBe(`token:${connection.item.live.id}:user:alice:publish`);
      expect(connection.url).toBe('ws://livekit.test');
      expect(live.media.rooms.has(connection.item.live.id)).toBe(true);
      expect(live.lifecycle.timeLimits.get(connection.item.live.id)).toEqual(new Date(clock.getTime() + LIVE_MAX_DURATION_MS));
      expect(live.lifecycle.hostChecks.get(connection.item.live.id)).toBe(HOST_FIRST_CONNECT_GRACE_MS);
      await vi.waitFor(() => expect([...notificationRepository.notifications.values()].filter((n) => n.type === 'live')).toHaveLength(2));
      const notification = [...notificationRepository.notifications.values()].find((n) => n.recipientId === 'bob');
      expect(notification).toMatchObject({ type: 'live', actorId: 'alice', liveId: connection.item.live.id, videoId: null });
    });

    it('un live déjà en cours est repris, sans nouvelle salle ni notification ; titre trop long refusé', async () => {
      const first = await live.service.start('alice', {});
      const again = await live.service.start('alice', { title: 'Autre' });
      expect(again.item.live.id).toBe(first.item.live.id);
      expect(live.repository.lives.size).toBe(1);
      await expect(live.service.start('bob', { title: 'x'.repeat(81) })).rejects.toBeInstanceOf(InvalidLiveTitleError);
    });

    it('serveur vidéo indisponible : rien ne reste en cours', async () => {
      live.media.failCreate = true;
      await expect(live.service.start('alice', {})).rejects.toBeInstanceOf(LiveMediaUnavailableError);
      const [stored] = live.repository.lives.values();
      expect(stored.status).toBe('ended');
      live.media.failCreate = false;
      await expect(live.service.start('alice', {})).resolves.toMatchObject({ role: 'host' });
    });

    it('10 lancements par jour au plus', async () => {
      for (let i = 0; i < 10; i++) {
        const { item } = await live.service.start('alice', {});
        await live.service.stop('alice', item.live.id);
      }
      await expect(live.service.start('alice', {})).rejects.toBeInstanceOf(TooManyLiveActionsError);
    });

    it('fin par l’auteur : salle fermée, fin annoncée, chat supprimé, chiffres gardés ; idempotent, réservée à l’auteur', async () => {
      const { item } = await live.service.start('alice', {});
      await live.service.sendMessage('bob', item.live.id, 'Salut');
      advance(90_000);
      await expect(live.service.stop('bob', item.live.id)).rejects.toBeInstanceOf(LiveNotFoundError);
      const ended = await live.service.stop('alice', item.live.id);
      expect(ended.live).toMatchObject({ status: 'ended', endReason: 'host' });
      expect(ended.stats?.durationSeconds).toBe(90);
      expect(live.media.rooms.size).toBe(0);
      expect(roomEvents('liveEnded')).toEqual([{ type: 'liveEnded', liveId: item.live.id, reason: 'host' }]);
      expect(live.repository.messages).toHaveLength(0);
      await expect(live.service.stop('alice', item.live.id)).resolves.toMatchObject({ live: { status: 'ended' } });
      expect(roomEvents('liveEnded')).toHaveLength(1);
      await expect(live.service.join(item.live.id, 'bob')).rejects.toBeInstanceOf(LiveEndedError);
      // Le live terminé reste lisible (écran « Live terminé »), ses chiffres pour son auteur seulement.
      await expect(live.service.getLive(item.live.id, 'bob')).resolves.not.toHaveProperty('stats');
    });
  });

  describe('spectateurs', () => {
    it('jeton de spectateur (regarder seulement), invité compris ; l’auteur qui revient peut publier', async () => {
      const { item } = await live.service.start('alice', {});
      await live.service.sendMessage('carol', item.live.id, 'Premier !');
      const viewer = await live.service.join(item.live.id, 'bob');
      expect(viewer.role).toBe('viewer');
      expect(viewer.token).toBe(`token:${item.live.id}:user:bob:subscribe`);
      expect(viewer.recentMessages.map(({ message, author }) => [author.id, message.content])).toEqual([['carol', 'Premier !']]);
      expect(viewer.item.stats).toBeUndefined();
      const guest = await live.service.join(item.live.id, null);
      expect(guest.token).toBe(`token:${item.live.id}:guest:invite-1:subscribe`);
      const host = await live.service.join(item.live.id, 'alice');
      expect(host.role).toBe('host');
      expect(host.token).toMatch(/:publish$/);
    });

    it('blocage dans un sens ou dans l’autre, ou auteur suspendu : introuvable', async () => {
      const { item } = await live.service.start('alice', {});
      await interactions.setBlock('alice', 'bob', true);
      await expect(live.service.join(item.live.id, 'bob')).rejects.toBeInstanceOf(LiveNotFoundError);
      await expect(live.service.getLive(item.live.id, 'bob')).rejects.toBeInstanceOf(LiveNotFoundError);
      await interactions.setBlock('carol', 'alice', true);
      await expect(live.service.join(item.live.id, 'carol')).rejects.toBeInstanceOf(LiveNotFoundError);
      await suspended.add('alice');
      await expect(live.service.join(item.live.id, null)).rejects.toBeInstanceOf(LiveNotFoundError);
    });

    it('rangée : lives en cours des comptes suivis ; anneau du profil, masqué en cas de blocage', async () => {
      await interactions.setFollow('bob', 'alice', true);
      await interactions.setFollow('bob', 'carol', true);
      const alice = await live.service.start('alice', {});
      advance(1000);
      const carol = await live.service.start('carol', {});
      await live.service.start('dave', {});
      expect((await live.service.listFollowingLives('bob')).map((entry) => entry.live.id)).toEqual([carol.item.live.id, alice.item.live.id]);
      expect([...(await live.service.getLiveRings(['alice', 'dave', 'bob'], null)).keys()].sort()).toEqual(['alice', 'dave']);
      await interactions.setBlock('dave', 'bob', true);
      expect((await live.service.getLiveRings(['dave'], 'bob')).size).toBe(0);
    });

    it('webhook : spectateurs distincts et pic (sans l’auteur) ; départ de l’auteur, puis vérification', async () => {
      const { item } = await live.service.start('alice', {});
      const id = item.live.id;
      await live.service.handleMediaEvent({ type: 'participantJoined', liveId: id, identity: 'user:alice', participantsCount: 1 });
      await live.service.handleMediaEvent({ type: 'participantJoined', liveId: id, identity: 'user:bob', participantsCount: 2 });
      await live.service.handleMediaEvent({ type: 'participantJoined', liveId: id, identity: 'guest:x', participantsCount: 3 });
      await live.service.handleMediaEvent({ type: 'participantLeft', liveId: id, identity: 'user:bob' });
      await live.service.handleMediaEvent({ type: 'participantJoined', liveId: id, identity: 'user:bob', participantsCount: 3 });
      const stats = (await live.service.getLive(id, 'alice')).stats;
      expect(stats).toMatchObject({ peakViewers: 2, viewersCount: 2 });

      live.lifecycle.hostChecks.clear();
      await live.service.handleMediaEvent({ type: 'participantLeft', liveId: id, identity: 'user:alice' });
      expect(live.lifecycle.hostChecks.get(id)).toBe(HOST_RECONNECT_GRACE_MS);
      // Revenu à temps : rien ne change.
      live.media.connected.add(`${id}|user:alice`);
      await expect(live.service.checkHost(id)).resolves.toBe(false);
      // Pas revenu : le live s'arrête.
      live.media.connected.clear();
      await expect(live.service.checkHost(id)).resolves.toBe(true);
      expect((await live.repository.findById(id))?.endReason).toBe('disconnected');
    });

    it('salle fermée par le serveur, durée maximale, maintenance (salle disparue, job perdu)', async () => {
      const a = await live.service.start('alice', {});
      await live.service.handleMediaEvent({ type: 'roomFinished', liveId: a.item.live.id });
      expect((await live.repository.findById(a.item.live.id))?.endReason).toBe('disconnected');

      const b = await live.service.start('bob', {});
      await expect(live.service.reachTimeLimit(b.item.live.id)).resolves.toBe(true);
      expect((await live.repository.findById(b.item.live.id))?.endReason).toBe('timeLimit');

      const c = await live.service.start('carol', {});
      const d = await live.service.start('dave', {});
      const e = await live.service.start('erin', {});
      live.media.rooms.delete(d.item.live.id);
      live.media.connected.add(`${e.item.live.id}|user:erin`);
      live.lifecycle.hostChecks.clear();
      // Trop tôt : laissé à sa vérification programmée.
      await expect(live.service.runMaintenance()).resolves.toEqual({ ended: 0, hostChecks: 0 });
      advance(HOST_FIRST_CONNECT_GRACE_MS);
      // Salle disparue : arrêté ; auteur absent de sa salle (job perdu) : vérification reprogrammée ; auteur présent : rien.
      await expect(live.service.runMaintenance()).resolves.toEqual({ ended: 1, hostChecks: 1 });
      expect((await live.repository.findById(d.item.live.id))?.status).toBe('ended');
      expect([...live.lifecycle.hostChecks.keys()]).toEqual([c.item.live.id]);
      advance(LIVE_MAX_DURATION_MS);
      await expect(live.service.runMaintenance()).resolves.toEqual({ ended: 2, hostChecks: 0 });
      expect((await live.repository.findById(c.item.live.id))?.endReason).toBe('timeLimit');
    });
  });

  describe('chat et cœurs', () => {
    it('message diffusé dans la salle, nettoyé ; longueur et limite de débit', async () => {
      const { item } = await live.service.start('alice', {});
      const sent = await live.service.sendMessage('bob', item.live.id, '  Coucou  ');
      expect(sent.message.content).toBe('Coucou');
      expect(roomEvents('chatMessage')).toEqual([
        { type: 'chatMessage', liveId: item.live.id, messageId: sent.message.id, content: 'Coucou', author: 'bob' },
      ]);
      await expect(live.service.sendMessage('bob', item.live.id, '   ')).rejects.toBeInstanceOf(InvalidLiveMessageError);
      await expect(live.service.sendMessage('bob', item.live.id, 'x'.repeat(MAX_LIVE_MESSAGE_LENGTH + 1))).rejects.toBeInstanceOf(
        InvalidLiveMessageError,
      );
      for (let i = 1; i < 20; i++) await live.service.sendMessage('bob', item.live.id, `m${i}`);
      await expect(live.service.sendMessage('bob', item.live.id, 'de trop')).rejects.toBeInstanceOf(TooManyLiveActionsError);
    });

    it('retrait par l’auteur du message ou celui du live, annoncé ; pas par un autre', async () => {
      const { item } = await live.service.start('alice', {});
      const first = await live.service.sendMessage('bob', item.live.id, 'Un');
      const second = await live.service.sendMessage('bob', item.live.id, 'Deux');
      await expect(live.service.deleteMessage('carol', item.live.id, first.message.id)).rejects.toBeInstanceOf(LiveMessageForbiddenError);
      await live.service.deleteMessage('bob', item.live.id, first.message.id);
      await live.service.deleteMessage('alice', item.live.id, second.message.id);
      expect(roomEvents('chatMessageDeleted')).toHaveLength(2);
      expect(live.repository.messages).toHaveLength(0);
    });

    it('cœurs par lots : total du live, diffusé ; pas sur son live, ni sur un live terminé', async () => {
      const { item } = await live.service.start('alice', {});
      await expect(live.service.sendHearts('bob', item.live.id, 5)).resolves.toBe(5);
      await expect(live.service.sendHearts('carol', item.live.id, 3)).resolves.toBe(8);
      expect(roomEvents('hearts').at(-1)).toEqual({ type: 'hearts', liveId: item.live.id, count: 3, total: 8 });
      await expect(live.service.sendHearts('bob', item.live.id, 0)).rejects.toBeInstanceOf(InvalidHeartsCountError);
      await expect(live.service.sendHearts('bob', item.live.id, 31)).rejects.toBeInstanceOf(InvalidHeartsCountError);
      await expect(live.service.sendHearts('alice', item.live.id, 1)).rejects.toBeInstanceOf(OwnLiveError);
      await live.service.stop('alice', item.live.id);
      await expect(live.service.sendHearts('bob', item.live.id, 1)).rejects.toBeInstanceOf(LiveEndedError);
    });
  });

  describe('pour les autres modules', () => {
    it('cadeaux : live où l’on peut offrir, cadeau compté et annoncé', async () => {
      const { item } = await live.service.start('alice', {});
      await expect(live.service.getGiftableLive('alice', item.live.id)).rejects.toBeInstanceOf(OwnLiveError);
      await expect(live.service.getGiftableLive('bob', item.live.id)).resolves.toMatchObject({ hostId: 'alice' });
      await live.service.recordGift(item.live.id, 'bob', { code: 'rose', amount: 1 });
      await live.service.recordGift(item.live.id, 'carol', { code: 'crown', amount: 50 });
      expect(roomEvents('gift').at(-1)).toMatchObject({ sender: 'carol', code: 'crown', giftsCount: 2, giftsAmount: 51 });
      expect((await live.service.getLive(item.live.id, 'alice')).stats).toMatchObject({ giftsCount: 2, giftsAmount: 51 });
      await live.service.stop('alice', item.live.id);
      await expect(live.service.getGiftableLive('bob', item.live.id)).rejects.toBeInstanceOf(LiveEndedError);
    });

    it('messagerie : aperçus (en cours ou terminés), sauf masqués ; partage d’un live en cours seulement', async () => {
      const { item } = await live.service.start('alice', {});
      const previews = await live.service.getLivePreviews([item.live.id, 'inconnu'], 'bob');
      expect([...previews.keys()]).toEqual([item.live.id]);
      await interactions.setBlock('bob', 'alice', true);
      expect((await live.service.getLivePreviews([item.live.id], 'bob')).size).toBe(0);
      await live.service.stop('alice', item.live.id);
      await expect(live.service.getVisibleLive('carol', item.live.id)).rejects.toBeInstanceOf(LiveNotFoundError);
    });

    it('modération : arrêt par un administrateur, à la suspension ; salle d’un compte supprimé fermée', async () => {
      const a = await live.service.start('alice', {});
      await expect(live.service.removeLive(a.item.live.id)).resolves.toBe(true);
      await expect(live.service.removeLive(a.item.live.id)).resolves.toBe(false);
      expect((await live.repository.findById(a.item.live.id))?.endReason).toBe('moderation');
      const b = await live.service.start('bob', {});
      await live.service.endForSuspension('bob');
      expect((await live.repository.findById(b.item.live.id))?.endReason).toBe('suspension');
      const c = await live.service.start('carol', {});
      await live.service.closeRoomsOf('carol');
      expect(live.media.rooms.has(c.item.live.id)).toBe(false);
    });
  });
});
