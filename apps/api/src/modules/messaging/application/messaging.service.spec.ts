import { beforeEach, describe, expect, it } from 'vitest';
import { InteractionsService } from '../../interactions/application/interactions.service';
import { InMemoryInteractionRepository } from '../../interactions/infrastructure/in-memory-interaction.repository';
import { NotificationsService } from '../../notifications/application/notifications.service';
import { InMemoryNotificationPublisher } from '../../notifications/infrastructure/in-memory-notification-publisher';
import { InMemoryNotificationRepository } from '../../notifications/infrastructure/in-memory-notification.repository';
import { UsersService } from '../../users/application/users.service';
import type { User } from '../../users/domain/user';
import { InMemoryUserRepository } from '../../users/infrastructure/in-memory-user.repository';
import { InMemoryAvatarStorage } from '../../users/infrastructure/in-memory-avatar-storage';
import { InMemoryAccountContentCleanup } from '../../users/infrastructure/in-memory-account-content-cleanup';
import { VideosService } from '../../videos/application/videos.service';
import { TranscodingQueue } from '../../videos/domain/transcoding-queue';
import { InMemoryVideoEventPublisher } from '../../videos/infrastructure/in-memory-video-event-publisher';
import { InMemoryVideoCleanupQueue } from '../../videos/infrastructure/in-memory-video-cleanup-queue';
import { InMemoryVideoRepository } from '../../videos/infrastructure/in-memory-video.repository';
import { InMemoryVideoStorage } from '../../videos/infrastructure/in-memory-video-storage';
import { MESSAGE_RATE_LIMITS, REQUEST_MESSAGE_LIMIT, REQUEST_RATE_LIMITS } from '../domain/messaging';
import {
  BlockedConversationError,
  CannotMessageYourselfError,
  ConversationNotFoundError,
  EmptyMessageError,
  MessageNotFoundError,
  NotAPendingRequestError,
  NotMessageSenderError,
  RateLimitedError,
  RecipientNotFoundError,
  RequestLimitReachedError,
  SharedVideoNotFoundError,
} from '../domain/messaging.errors';
import { InMemoryConversationRepository } from '../infrastructure/in-memory-conversation.repository';
import { InMemoryMessagingEventPublisher } from '../infrastructure/in-memory-messaging-event-publisher';
import { InMemoryRateLimiter } from '../../../rate-limit/in-memory-rate-limiter';
import { MessagingService } from './messaging.service';

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
const EXTRA_USERS = Array.from({ length: 12 }, (_, i) => `u${i + 1}`);

describe('MessagingService', () => {
  let clock: number;
  let conversations: InMemoryConversationRepository;
  let videoRepository: InMemoryVideoRepository;
  let events: InMemoryMessagingEventPublisher;
  let interactions: InteractionsService;
  let service: MessagingService;

  const befriend = async (a: string, b: string) => {
    await interactions.setFollow(a, b, true);
    await interactions.setFollow(b, a, true);
  };
  const open = async (from: string, to: string) => (await service.openConversation(from, to)).conversation.id;
  const send = (from: string, id: string, content: string) => service.sendMessage(from, id, { content });
  const eventsOf = (name: string) => events.events.filter((e) => e.event === name).map((e) => [e.recipientId, e.detail]);

  beforeEach(async () => {
    clock = Date.UTC(2026, 8, 25, 10, 0, 0);
    const userRepository = new InMemoryUserRepository(['alice', 'bob', 'carol', ...EXTRA_USERS].map(user));
    videoRepository = new InMemoryVideoRepository();
    const users = new UsersService(userRepository, new InMemoryAvatarStorage(), new InMemoryAccountContentCleanup());
    const videos = new VideosService(videoRepository, new InMemoryVideoStorage(), new NoopTranscodingQueue(), new InMemoryVideoEventPublisher(), new InMemoryVideoCleanupQueue());
    const notifications = new NotificationsService(new InMemoryNotificationRepository(), users, videos, new InMemoryNotificationPublisher());
    interactions = new InteractionsService(new InMemoryInteractionRepository(videoRepository, userRepository), videos, users, notifications, new InMemoryRateLimiter());
    conversations = new InMemoryConversationRepository();
    events = new InMemoryMessagingEventPublisher();
    service = new MessagingService(conversations, users, interactions, videos, events, new InMemoryRateLimiter(() => clock), () => clock);
    await befriend('alice', 'bob');
  });

  describe('ouverture', () => {
    it('crée la conversation une seule fois, quel que soit celui qui l’ouvre', async () => {
      const opened = await service.openConversation('alice', 'bob');
      expect(opened).toMatchObject({ participant: { id: 'bob' }, status: 'direct', canSend: true, lastMessage: null, remainingRequestMessages: null });
      await expect(open('bob', 'alice')).resolves.toBe(opened.conversation.id);
      expect(conversations.conversations.size).toBe(1);
    });

    it('refuse soi-même et un pseudo inconnu', async () => {
      await expect(service.openConversation('alice', 'alice')).rejects.toBeInstanceOf(CannotMessageYourselfError);
      await expect(service.openConversation('alice', 'inconnu')).rejects.toBeInstanceOf(RecipientNotFoundError);
    });

    it('sans follow mutuel : le premier message sera une demande', async () => {
      await expect(service.openConversation('carol', 'alice')).resolves.toMatchObject({ status: 'requestSent', canSend: true, remainingRequestMessages: 3 });
    });
  });

  describe('envoi entre abonnés mutuels', () => {
    it('prévient les deux participants avec leurs badges, notifie le destinataire, accepte la conversation', async () => {
      const id = await open('alice', 'bob');
      const { message } = await send('alice', id, '  Salut !  ');

      expect(message).toMatchObject({ conversationId: id, senderId: 'alice', content: 'Salut !', sharedVideoId: null });
      expect(events.events).toEqual([
        { recipientId: 'alice', event: 'messageCreated', detail: 'Salut !', badges: { unreadConversations: 0, pendingRequests: 0 } },
        { recipientId: 'bob', event: 'messageCreated', detail: 'Salut !', badges: { unreadConversations: 1, pendingRequests: 0 } },
      ]);
      expect(events.pushes).toEqual([{ recipientId: 'bob', senderId: 'alice', content: 'Salut !', asRequest: false }]);
      expect(await service.getConversation('bob', id)).toMatchObject({
        status: 'direct',
        conversation: { unreadCount: 1, accepted: true },
        participantLastReadMessageId: message.id,
      });
    });

    it('une conversation acceptée reste libre après un unfollow', async () => {
      const id = await open('alice', 'bob');
      await send('bob', id, 'avant');
      await interactions.setFollow('bob', 'alice', false);
      await expect(send('alice', id, 'après')).resolves.toBeDefined();
      expect((await service.getConversation('alice', id)).status).toBe('direct');
    });

    it('refuse un message vide et un non-participant', async () => {
      const id = await open('alice', 'bob');
      await expect(send('alice', id, '   ')).rejects.toBeInstanceOf(EmptyMessageError);
      await expect(service.sendMessage('alice', id, {})).rejects.toBeInstanceOf(EmptyMessageError);
      await expect(send('carol', id, 'intrus')).rejects.toBeInstanceOf(ConversationNotFoundError);
      await expect(service.listMessages('carol', id, null, 10)).rejects.toBeInstanceOf(ConversationNotFoundError);
      await expect(service.getConversation('carol', id)).rejects.toBeInstanceOf(ConversationNotFoundError);
    });
  });

  describe('demandes de message', () => {
    it('hors abonnés mutuels : demande dans l’onglet du destinataire, limitée, sans « Vu »', async () => {
      const id = await open('carol', 'alice');
      await send('carol', id, 'd1');

      expect((await service.listRequests('alice', null, 10)).items.map((i) => [i.participant.id, i.status])).toEqual([['carol', 'requestReceived']]);
      expect((await service.listConversations('alice', null, 10)).items).toEqual([]);
      expect((await service.listConversations('carol', null, 10)).items.map((i) => i.status)).toEqual(['requestSent']);
      await expect(service.badges('alice')).resolves.toEqual({ unreadConversations: 0, pendingRequests: 1 });
      expect(events.pushes).toEqual([{ recipientId: 'alice', senderId: 'carol', content: 'd1', asRequest: true }]);

      await send('carol', id, 'd2');
      await send('carol', id, 'd3');
      expect((await service.getConversation('carol', id))).toMatchObject({ remainingRequestMessages: 0, canSend: false });
      await expect(send('carol', id, 'd4')).rejects.toBeInstanceOf(RequestLimitReachedError);

      // Lire une demande ne prévient pas l'expéditeur, et « Vu » reste masqué.
      events.events.length = 0;
      await service.markRead('alice', id, null);
      expect(eventsOf('conversationRead')).toEqual([['alice', expect.stringContaining('alice:')]]);
      expect((await service.getConversation('carol', id)).participantLastReadMessageId).toBeNull();
    });

    it('accepter : conversation libre pour les deux, sans limite', async () => {
      const id = await open('carol', 'alice');
      for (const text of ['d1', 'd2', 'd3']) await send('carol', id, text);
      events.events.length = 0;

      await expect(service.acceptRequest('alice', id)).resolves.toMatchObject({ status: 'direct', canSend: true });
      expect(eventsOf('conversationAccepted')).toEqual([['alice', id], ['carol', id]]);
      await expect(send('carol', id, 'd4')).resolves.toBeDefined();
      expect((await service.listConversations('alice', null, 10)).items.map((i) => i.participant.id)).toEqual(['carol']);
      await expect(service.acceptRequest('alice', id)).rejects.toBeInstanceOf(NotAPendingRequestError);
      await expect(service.acceptRequest('carol', id)).rejects.toBeInstanceOf(NotAPendingRequestError);
    });

    it('répondre à une demande l’accepte', async () => {
      const id = await open('carol', 'alice');
      await send('carol', id, 'bonjour ?');
      await send('alice', id, 'bonjour !');
      expect((await service.getConversation('carol', id)).status).toBe('direct');
      expect(eventsOf('conversationAccepted')).toEqual([['alice', id], ['carol', id]]);
      expect(events.pushes.at(-1)).toMatchObject({ recipientId: 'carol', asRequest: false });
    });

    it('refuser : la demande disparaît, ses messages suivants ne sont plus remis, l’expéditeur n’en sait rien', async () => {
      const id = await open('carol', 'alice');
      await send('carol', id, 'd1');
      await service.declineRequest('alice', id);
      expect((await service.listRequests('alice', null, 10)).items).toEqual([]);
      await expect(service.badges('alice')).resolves.toEqual({ unreadConversations: 0, pendingRequests: 0 });

      events.events.length = 0;
      events.pushes.length = 0;
      await send('carol', id, 'd2');
      expect(events.events.map((e) => e.recipientId)).toEqual(['carol']);
      expect(events.pushes).toEqual([]);
      expect((await service.getConversation('carol', id)).status).toBe('requestSent');
      expect((await service.listRequests('alice', null, 10)).items).toEqual([]);
    });
  });

  describe('blocage', () => {
    it('plus aucun envoi dans les deux sens ; historique lisible', async () => {
      const id = await open('alice', 'bob');
      await send('bob', id, 'avant');
      await interactions.setBlock('alice', 'bob', true);

      await expect(send('alice', id, 'x')).rejects.toBeInstanceOf(BlockedConversationError);
      await expect(send('bob', id, 'x')).rejects.toBeInstanceOf(BlockedConversationError);
      expect(await service.getConversation('alice', id)).toMatchObject({ canSend: false, blockedByMe: true });
      expect(await service.getConversation('bob', id)).toMatchObject({ canSend: false, blockedByMe: false });
      expect((await service.listMessages('bob', id, null, 10)).items.map((i) => i.message.content)).toEqual(['avant']);
    });

    it('masque les demandes des comptes bloqués et ne relaie pas « en train d’écrire »', async () => {
      const id = await open('carol', 'alice');
      await send('carol', id, 'spam');
      await interactions.setBlock('alice', 'carol', true);
      expect((await service.listRequests('alice', null, 10)).items).toEqual([]);
      await expect(service.badges('alice')).resolves.toMatchObject({ pendingRequests: 0 });

      const withBob = await open('alice', 'bob');
      await send('alice', withBob, 'hello');
      await interactions.setBlock('bob', 'alice', true);
      events.events.length = 0;
      await service.typing('alice', withBob);
      expect(eventsOf('typing')).toEqual([]);
    });
  });

  describe('suppression', () => {
    it('l’expéditeur retire son message pour les deux', async () => {
      const id = await open('alice', 'bob');
      const { message } = await send('alice', id, 'oups');
      await send('bob', id, 'réponse');
      events.events.length = 0;

      await expect(service.deleteMessage('bob', message.id)).rejects.toBeInstanceOf(NotMessageSenderError);
      await expect(service.deleteMessage('carol', message.id)).rejects.toBeInstanceOf(MessageNotFoundError);
      await service.deleteMessage('alice', message.id);

      expect(eventsOf('messageDeleted')).toEqual([['alice', message.id], ['bob', message.id]]);
      expect((await service.listMessages('bob', id, null, 10)).items.map((i) => i.message.content)).toEqual(['réponse']);
      await expect(service.deleteMessage('alice', message.id)).rejects.toBeInstanceOf(MessageNotFoundError);
    });

    it('supprimer une conversation ne la supprime que pour soi ; elle réapparaît au message suivant', async () => {
      const id = await open('alice', 'bob');
      await send('bob', id, 'm1');
      await send('alice', id, 'm2');
      await service.deleteConversation('alice', id);

      expect(eventsOf('conversationDeleted')).toEqual([['alice', id]]);
      expect((await service.listConversations('alice', null, 10)).items).toEqual([]);
      expect((await service.listMessages('alice', id, null, 10)).items).toEqual([]);
      expect((await service.listMessages('bob', id, null, 10)).items).toHaveLength(2);

      await send('bob', id, 'm3');
      const [back] = (await service.listConversations('alice', null, 10)).items;
      expect(back).toMatchObject({ lastMessage: { message: { content: 'm3' } }, conversation: { unreadCount: 1 } });
      expect((await service.listMessages('alice', id, null, 10)).items.map((i) => i.message.content)).toEqual(['m3']);
    });
  });

  describe('partage de vidéo', () => {
    async function publishedVideo(author: string) {
      const created = await videoRepository.create({ userId: author, description: 'ma vidéo', rawKey: 'k', uploadId: 'u', rawSize: 1 });
      Object.assign(videoRepository.videos.get(created.id)!, { status: 'ready', hlsUrl: 'h.m3u8', thumbnailUrl: 't.jpg' });
      return created.id;
    }

    it('partage une vidéo publiée (compté comme un partage), avec ou sans texte', async () => {
      const video = await publishedVideo('carol');
      const id = await open('alice', 'bob');
      const shared = await service.sendMessage('alice', id, { videoId: video });

      expect(shared.message).toMatchObject({ content: '', sharedVideoId: video });
      expect(shared.sharedVideo).toMatchObject({ id: video, video: { hlsUrl: 'h.m3u8' }, author: { id: 'carol' } });
      expect((await videoRepository.findPublishedByIds([video]))[0]!.sharesCount).toBe(1);
      await expect(service.sendMessage('alice', id, { content: 'regarde', videoId: video })).resolves.toMatchObject({ message: { content: 'regarde' } });
      expect(events.pushes.map((p) => p.content)).toEqual(['', 'regarde']);
    });

    it('refuse une vidéo inconnue ; une vidéo supprimée depuis devient indisponible', async () => {
      const id = await open('alice', 'bob');
      await expect(service.sendMessage('alice', id, { videoId: 'inconnue' })).rejects.toBeInstanceOf(SharedVideoNotFoundError);

      const video = await publishedVideo('carol');
      await service.sendMessage('alice', id, { videoId: video });
      await videoRepository.delete(video);
      const [item] = (await service.listMessages('bob', id, null, 10)).items;
      expect(item!.sharedVideo).toEqual({ id: video, video: null, author: null });
    });

    it("vidéo d'un compte bloqué : refusée à l'envoi, indisponible pour le destinataire concerné", async () => {
      const video = await publishedVideo('carol');
      const id = await open('alice', 'bob');
      await interactions.setBlock('carol', 'bob', true);
      await service.sendMessage('alice', id, { videoId: video });

      const shared = (viewer: string) => events.created.find((c) => c.recipientId === viewer)!.item.sharedVideo;
      expect(shared('alice')).toMatchObject({ id: video, video: { id: video }, author: { id: 'carol' } });
      expect(shared('bob')).toEqual({ id: video, video: null, author: null });
      expect((await service.listMessages('bob', id, null, 10)).items[0]!.sharedVideo).toEqual({ id: video, video: null, author: null });
      expect((await service.listMessages('alice', id, null, 10)).items[0]!.sharedVideo).toMatchObject({ author: { id: 'carol' } });
      expect((await service.listConversations('bob', null, 10)).items[0]!.lastMessage!.sharedVideo).toMatchObject({ video: null });

      await expect(service.sendMessage('bob', id, { videoId: video })).rejects.toBeInstanceOf(SharedVideoNotFoundError);
    });
  });

  describe('limites d’envoi', () => {
    it(`${MESSAGE_RATE_LIMITS[0]!.limit} messages par minute, puis 429 jusqu’à la minute suivante`, async () => {
      const id = await open('alice', 'bob');
      for (let i = 0; i < MESSAGE_RATE_LIMITS[0]!.limit; i++) await send('alice', id, `m${i}`);
      const refused = await send('alice', id, 'de trop').catch((error: unknown) => error);
      expect(refused).toBeInstanceOf(RateLimitedError);
      expect((refused as RateLimitedError).retryAfterSeconds).toBe(60);
      // Chaque compte a ses propres limites.
      await expect(send('bob', id, 'moi je peux')).resolves.toBeDefined();

      clock += 60_000;
      await expect(send('alice', id, 'de nouveau')).resolves.toBeDefined();
    });

    it(`${REQUEST_RATE_LIMITS[0]!.limit} nouvelles demandes par jour`, async () => {
      const limit = REQUEST_RATE_LIMITS[0]!.limit;
      for (const target of EXTRA_USERS.slice(0, limit)) await send('carol', await open('carol', target), 'salut');
      const next = await open('carol', EXTRA_USERS[limit]!);
      await expect(send('carol', next, 'salut')).rejects.toBeInstanceOf(RateLimitedError);
      // La limite porte sur les nouvelles demandes, pas sur les messages d'une demande ouverte.
      await expect(send('carol', await open('carol', 'u1'), 'relance')).resolves.toBeDefined();
      expect(REQUEST_MESSAGE_LIMIT).toBe(3);
    });
  });

  describe('en train d’écrire', () => {
    it('relayé à l’autre participant, au plus un toutes les 2 s, seulement dans une conversation libre', async () => {
      const id = await open('alice', 'bob');
      await service.typing('alice', id);
      await service.typing('alice', id);
      clock += 2_000;
      await service.typing('alice', id);
      expect(eventsOf('typing')).toEqual([['bob', 'alice'], ['bob', 'alice']]);

      const request = await open('carol', 'alice');
      await send('carol', request, 'd1');
      events.events.length = 0;
      await service.typing('carol', request);
      await service.typing('carol', 'inconnue');
      expect(eventsOf('typing')).toEqual([]);
    });
  });

  describe('listes et lecture', () => {
    it('boîte de réception : par dernière activité, sans conversation vide, page par page', async () => {
      await befriend('alice', 'carol');
      const withBob = await open('alice', 'bob');
      const withCarol = await open('alice', 'carol');
      await open('bob', 'carol'); // vide : n'apparaît pas

      await send('alice', withBob, 'b1');
      await send('carol', withCarol, 'c1');
      await send('bob', withBob, 'b2');

      const first = await service.listConversations('alice', null, 1);
      const second = await service.listConversations('alice', first.nextCursor, 1);
      expect(first.items.map((i) => [i.participant.id, i.lastMessage?.message.content])).toEqual([['bob', 'b2']]);
      expect(second.items.map((i) => [i.participant.id, i.lastMessage?.message.content])).toEqual([['carol', 'c1']]);
      expect(second.nextCursor).toBeNull();
      await expect(service.badges('alice')).resolves.toEqual({ unreadConversations: 2, pendingRequests: 0 });
    });

    it('lu jusqu’au message affiché, « Vu » chez l’autre, jamais en arrière', async () => {
      const id = await open('alice', 'bob');
      const { message: m1 } = await send('alice', id, 'm1');
      const { message: m2 } = await send('alice', id, 'm2');
      events.events.length = 0;

      await expect(service.markRead('bob', id, m1.id)).resolves.toEqual({ unreadConversations: 1, pendingRequests: 0 });
      await expect(service.markRead('bob', id, null)).resolves.toEqual({ unreadConversations: 0, pendingRequests: 0 });
      expect((await service.getConversation('alice', id)).participantLastReadMessageId).toBe(m2.id);
      expect(eventsOf('conversationRead')).toEqual([
        ['bob', `bob:${m1.id}`],
        ['alice', `bob:${m1.id}`],
        ['bob', `bob:${m2.id}`],
        ['alice', `bob:${m2.id}`],
      ]);
      await service.markRead('bob', id, m1.id);
      expect(eventsOf('conversationRead')).toHaveLength(4);
    });
  });

  it('autre participant supprimé : conversation supprimée avec ses messages', async () => {
    const id = await open('alice', 'bob');
    await send('alice', id, 'm1');
    conversations.removeUser('bob');

    expect(conversations.conversations.size).toBe(0);
    expect((await service.listConversations('alice', null, 10)).items).toEqual([]);
    await expect(service.getConversation('alice', id)).rejects.toBeInstanceOf(ConversationNotFoundError);
  });
});
