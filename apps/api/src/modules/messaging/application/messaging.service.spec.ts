import { beforeEach, describe, expect, it } from 'vitest';
import { inMemoryStories, publishTestStory } from '../../stories/infrastructure/in-memory-stories';
import { InMemoryProfileCountersPublisher } from '../../interactions/infrastructure/in-memory-profile-counters-publisher';
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
import { InMemoryInterestRepository } from '../../users/infrastructure/in-memory-interest.repository';
import { VideosService } from '../../videos/application/videos.service';
import { TranscodingQueue } from '../../videos/domain/transcoding-queue';
import { InMemoryVideoEventPublisher } from '../../videos/infrastructure/in-memory-video-event-publisher';
import { InMemoryVideoCleanupQueue } from '../../videos/infrastructure/in-memory-video-cleanup-queue';
import { InMemoryVideoRepository } from '../../videos/infrastructure/in-memory-video.repository';
import { InMemoryVideoStorage } from '../../videos/infrastructure/in-memory-video-storage';
import { GROUP_CREATE_RATE_LIMITS, MAX_GROUP_MEMBERS, MESSAGE_RATE_LIMITS, REQUEST_MESSAGE_LIMIT, REQUEST_RATE_LIMITS } from '../domain/messaging';
import {
  BlockedConversationError,
  CannotMessageYourselfError,
  ClientMessageIdConflictError,
  ConversationNotFoundError,
  EmptyMessageError,
  GroupFullError,
  GroupMemberNotFoundError,
  InvalidGroupError,
  NotAFriendError,
  NotAGroupError,
  NotGroupAdminError,
  RepliedStoryNotFoundError,
  SharedLiveNotFoundError,
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
import { InMemorySuspendedAccounts } from '../../../suspension/in-memory-suspended-accounts';
import { inMemoryLive } from '../../live/infrastructure/in-memory-live';
import { InMemoryReceivedLikesCounter } from '../../users/infrastructure/in-memory-received-likes-counter';

// Registre des comptes suspendus (ADR-037), partagé par les services d'un même test.
let suspended = new InMemorySuspendedAccounts();

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
  let stories: ReturnType<typeof inMemoryStories>;
  let lives: ReturnType<typeof inMemoryLive>;

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
    suspended = new InMemorySuspendedAccounts();
    const users = new UsersService(
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
    const notifications = new NotificationsService(
      new InMemoryNotificationRepository(),
      users,
      videos,
      new InMemoryNotificationPublisher(),
      suspended,
    );
    interactions = new InteractionsService(
      new InMemoryInteractionRepository(videoRepository, userRepository),
      videos,
      users,
      notifications,
      new InMemoryRateLimiter(),
      suspended,
      new InMemoryProfileCountersPublisher(),
    );
    conversations = new InMemoryConversationRepository();
    events = new InMemoryMessagingEventPublisher();
    stories = inMemoryStories(users, interactions, () => new Date(clock));
    lives = inMemoryLive(users, interactions, notifications, () => new Date(clock));
    service = new MessagingService(
      conversations,
      users,
      interactions,
      videos,
      stories.service,
      lives.service,
      events,
      new InMemoryRateLimiter(() => clock),
      () => clock,
    );
    await befriend('alice', 'bob');
  });

  describe('ouverture', () => {
    it('crée la conversation une seule fois, quel que soit celui qui l’ouvre', async () => {
      const opened = await service.openConversation('alice', 'bob');
      expect(opened).toMatchObject({
        participant: { id: 'bob' },
        status: 'direct',
        canSend: true,
        lastMessage: null,
        remainingRequestMessages: null,
      });
      await expect(open('bob', 'alice')).resolves.toBe(opened.conversation.id);
      expect(conversations.conversations.size).toBe(1);
    });

    it('refuse soi-même et un pseudo inconnu', async () => {
      await expect(service.openConversation('alice', 'alice')).rejects.toBeInstanceOf(CannotMessageYourselfError);
      await expect(service.openConversation('alice', 'inconnu')).rejects.toBeInstanceOf(RecipientNotFoundError);
    });

    it('sans follow mutuel : le premier message sera une demande', async () => {
      await expect(service.openConversation('carol', 'alice')).resolves.toMatchObject({
        status: 'requestSent',
        canSend: true,
        remainingRequestMessages: 3,
      });
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

  describe('identifiant d’envoi (ADR-044)', () => {
    const KEY = '0192f3a0-0000-7000-8000-0000000000aa';

    it('un renvoi avec le même identifiant rend le message déjà créé, sans second message ni événement ni comptage', async () => {
      const video = await videoRepository.create({ userId: 'carol', description: null, rawKey: 'k', uploadId: 'u', rawSize: 1 });
      Object.assign(videoRepository.videos.get(video.id)!, { status: 'ready', hlsUrl: 'h.m3u8', thumbnailUrl: 't.jpg' });
      const id = await open('alice', 'bob');
      const first = await service.sendMessage('alice', id, { content: 'Salut', videoId: video.id, clientMessageId: KEY });
      expect(first.clientMessageId).toBe(KEY);
      // L'écho de l'expéditeur porte l'identifiant, pas celui du destinataire.
      expect(events.created.map((c) => [c.recipientId, c.item.clientMessageId])).toEqual([
        ['alice', KEY],
        ['bob', undefined],
      ]);

      const again = await service.sendMessage('alice', id, { content: 'Salut', videoId: video.id, clientMessageId: KEY });
      expect(again).toMatchObject({ message: { id: first.message.id }, clientMessageId: KEY, sharedVideo: { id: video.id } });
      expect(conversations.messages).toHaveLength(1);
      expect(events.created).toHaveLength(2);
      expect(events.pushes).toHaveLength(1);
      expect((await videoRepository.findPublishedByIds([video.id]))[0].sharesCount).toBe(1);
      // Liste des messages : identifiant jamais exposé.
      expect((await service.listMessages('alice', id, null, 10)).items[0].clientMessageId).toBeUndefined();
    });

    it('renvoi accepté même si la conversation ne permet plus d’écrire ou la limite est atteinte (le message était parti)', async () => {
      const id = await open('alice', 'bob');
      const first = await service.sendMessage('alice', id, { content: 'avant', clientMessageId: KEY });
      for (let i = 1; i < MESSAGE_RATE_LIMITS[0].limit; i++) await send('alice', id, `m${i}`);
      await expect(send('alice', id, 'de trop')).rejects.toBeInstanceOf(RateLimitedError);
      await interactions.setBlock('bob', 'alice', true);
      await expect(service.sendMessage('alice', id, { content: 'avant', clientMessageId: KEY })).resolves.toMatchObject({
        message: { id: first.message.id },
      });
    });

    it('chaque compte a ses identifiants ; le même dans une autre conversation est refusé (409)', async () => {
      const id = await open('alice', 'bob');
      const other = await open('alice', 'carol');
      await service.sendMessage('alice', id, { content: 'un', clientMessageId: KEY });
      await expect(service.sendMessage('bob', id, { content: 'deux', clientMessageId: KEY })).resolves.toMatchObject({
        message: { senderId: 'bob' },
      });
      await expect(service.sendMessage('alice', other, { content: 'trois', clientMessageId: KEY })).rejects.toBeInstanceOf(
        ClientMessageIdConflictError,
      );
      // Sans identifiant : chaque envoi crée un message, comme avant.
      await send('alice', id, 'quatre');
      await send('alice', id, 'quatre');
      expect(conversations.messages.map((m) => m.content)).toEqual(['un', 'deux', 'quatre', 'quatre']);
    });

    it('message retiré depuis : le renvoi en crée un nouveau', async () => {
      const id = await open('alice', 'bob');
      const first = await service.sendMessage('alice', id, { content: 'oups', clientMessageId: KEY });
      await service.deleteMessage('alice', first.message.id);
      const again = await service.sendMessage('alice', id, { content: 'oups', clientMessageId: KEY });
      expect(again.message.id).not.toBe(first.message.id);
    });
  });

  describe('demandes de message', () => {
    it('hors abonnés mutuels : demande dans l’onglet du destinataire, limitée, sans « Vu »', async () => {
      const id = await open('carol', 'alice');
      await send('carol', id, 'd1');

      expect((await service.listRequests('alice', null, 10)).items.map((i) => [i.participant?.id, i.status])).toEqual([['carol', 'requestReceived']]);
      expect((await service.listConversations('alice', null, 10)).items).toEqual([]);
      expect((await service.listConversations('carol', null, 10)).items.map((i) => i.status)).toEqual(['requestSent']);
      await expect(service.badges('alice')).resolves.toEqual({ unreadConversations: 0, pendingRequests: 1 });
      expect(events.pushes).toEqual([{ recipientId: 'alice', senderId: 'carol', content: 'd1', asRequest: true }]);

      await send('carol', id, 'd2');
      await send('carol', id, 'd3');
      expect(await service.getConversation('carol', id)).toMatchObject({ remainingRequestMessages: 0, canSend: false });
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
      expect(eventsOf('conversationAccepted')).toEqual([
        ['alice', id],
        ['carol', id],
      ]);
      await expect(send('carol', id, 'd4')).resolves.toBeDefined();
      expect((await service.listConversations('alice', null, 10)).items.map((i) => i.participant?.id)).toEqual(['carol']);
      await expect(service.acceptRequest('alice', id)).rejects.toBeInstanceOf(NotAPendingRequestError);
      await expect(service.acceptRequest('carol', id)).rejects.toBeInstanceOf(NotAPendingRequestError);
    });

    it('répondre à une demande l’accepte', async () => {
      const id = await open('carol', 'alice');
      await send('carol', id, 'bonjour ?');
      await send('alice', id, 'bonjour !');
      expect((await service.getConversation('carol', id)).status).toBe('direct');
      expect(eventsOf('conversationAccepted')).toEqual([
        ['alice', id],
        ['carol', id],
      ]);
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

  describe('recherche dans les messages (ADR-058)', () => {
    it('ses conversations seulement, sans casse, du plus récent au plus ancien ; ni supprimés pour soi ni demandes refusées', async () => {
      await befriend('alice', 'bob');
      const withBob = await open('alice', 'bob');
      await send('alice', withBob, 'On se voit au Cinéma ?');
      await send('bob', withBob, 'oui, cinéma à 20 h');
      await send('bob', withBob, 'autre chose');
      const found = async (userId: string, q: string) =>
        (await service.searchMessages(userId, q, 20)).map((r) => [r.message.content, r.participant.username, r.sender.username]);
      expect(await found('alice', 'CINÉ')).toEqual([
        ['oui, cinéma à 20 h', 'bob', 'bob'],
        ['On se voit au Cinéma ?', 'bob', 'alice'],
      ]);
      expect(await found('bob', 'cinéma')).toHaveLength(2);
      // Ni les conversations des autres, ni les caractères de LIKE pris pour des jokers.
      expect(await found('carol', 'cinéma')).toEqual([]);
      expect(await found('alice', '%')).toEqual([]);
      expect(await service.searchMessages('alice', 'cinéma', 1)).toHaveLength(1);
      // Supprimée pour soi : plus rien, l'autre garde tout.
      await service.deleteConversation('alice', withBob);
      expect(await found('alice', 'cinéma')).toEqual([]);
      expect(await found('bob', 'cinéma')).toHaveLength(2);
      // Demande refusée : ses messages ne sont pas trouvés par celui qui l'a refusée.
      const fromCarol = await open('carol', 'alice');
      await send('carol', fromCarol, 'cinéma demain ?');
      expect(await found('alice', 'demain')).toEqual([['cinéma demain ?', 'carol', 'carol']]);
      await service.declineRequest('alice', fromCarol);
      expect(await found('alice', 'demain')).toEqual([]);
      expect(await found('carol', 'demain')).toHaveLength(1);
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

  describe('suspension (ADR-037)', () => {
    it("plus d'envoi vers un compte suspendu, ses demandes disparaissent ; historique lisible, rien ne dit « suspendu »", async () => {
      const id = await open('alice', 'bob');
      await send('bob', id, 'avant');
      const request = await open('carol', 'alice');
      await send('carol', request, 'spam');
      await suspended.add('bob');
      await suspended.add('carol');

      await expect(send('alice', id, 'x')).rejects.toBeInstanceOf(BlockedConversationError);
      expect(await service.getConversation('alice', id)).toMatchObject({ canSend: false, blockedByMe: false });
      expect((await service.listMessages('alice', id, null, 10)).items.map((i) => i.message.content)).toEqual(['avant']);
      expect((await service.listRequests('alice', null, 10)).items).toEqual([]);
      await expect(service.badges('alice')).resolves.toMatchObject({ pendingRequests: 0 });

      await suspended.remove('bob');
      expect(await service.getConversation('alice', id)).toMatchObject({ canSend: true });
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

      expect(eventsOf('messageDeleted')).toEqual([
        ['alice', message.id],
        ['bob', message.id],
      ]);
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

  describe('signalement et modération (ADR-038)', () => {
    it('un message n’est visible que des participants, et plus après avoir supprimé la conversation pour soi', async () => {
      const id = await open('alice', 'bob');
      const { message } = await send('bob', id, 'insulte');
      await expect(service.getVisibleMessage('alice', message.id)).resolves.toMatchObject({ senderId: 'bob', content: 'insulte' });
      await expect(service.getVisibleMessage('carol', message.id)).rejects.toBeInstanceOf(MessageNotFoundError);
      await service.deleteConversation('alice', id);
      await expect(service.getVisibleMessage('alice', message.id)).rejects.toBeInstanceOf(MessageNotFoundError);
      await expect(service.getMessages([message.id, message.id, 'inconnu'])).resolves.toMatchObject([{ id: message.id }]);
    });

    it('un administrateur retire un message pour les deux, comme son expéditeur', async () => {
      const id = await open('alice', 'bob');
      const { message } = await send('bob', id, 'insulte');
      events.events.length = 0;
      await expect(service.removeMessage(message.id)).resolves.toMatchObject({ id: message.id });
      expect(eventsOf('messageDeleted')).toEqual([
        ['alice', message.id],
        ['bob', message.id],
      ]);
      await expect(service.getMessages([message.id])).resolves.toEqual([]);
      await expect(service.removeMessage(message.id)).rejects.toBeInstanceOf(MessageNotFoundError);
    });
  });

  describe('réponse à une story (ADR-051)', () => {
    it('répond à la story active de l’autre participant, avec un texte ; elle devient « expirée » ensuite', async () => {
      const story = await publishTestStory(stories, 'bob');
      const id = await open('alice', 'bob');
      const reply = await service.sendMessage('alice', id, { content: 'Trop bien !', storyId: story.id });
      expect(reply.message).toMatchObject({ content: 'Trop bien !', storyId: story.id });
      expect(reply.repliedStory).toEqual({ id: story.id, story: expect.objectContaining({ id: story.id, mediaType: 'photo' }) });
      expect(events.pushes.at(-1)).toMatchObject({ recipientId: 'bob', content: 'Trop bien !' });

      clock += 24 * 3600 * 1000;
      const [item] = (await service.listMessages('bob', id, null, 10)).items;
      expect(item.repliedStory).toEqual({ id: story.id, story: null });
    });

    it('refuse une réponse sans texte, à une story inconnue, ou à celle d’un autre compte', async () => {
      const story = await publishTestStory(stories, 'bob');
      const carolStory = await publishTestStory(stories, 'carol');
      const id = await open('alice', 'bob');
      await expect(service.sendMessage('alice', id, { content: '  ', storyId: story.id })).rejects.toBeInstanceOf(EmptyMessageError);
      await expect(service.sendMessage('alice', id, { content: 'Salut', storyId: carolStory.id })).rejects.toBeInstanceOf(RepliedStoryNotFoundError);
      await expect(service.sendMessage('alice', id, { content: 'Salut', storyId: '00000000-0000-7000-8000-000000000999' })).rejects.toBeInstanceOf(
        RepliedStoryNotFoundError,
      );
      // Sa propre story : l'autre participant n'en est pas l'auteur.
      const own = await publishTestStory(stories, 'alice');
      await expect(service.sendMessage('alice', id, { content: 'Moi', storyId: own.id })).rejects.toBeInstanceOf(RepliedStoryNotFoundError);
    });
  });

  describe('partage d’un live (ADR-053)', () => {
    it('partage un live en cours, sans texte ; il devient indisponible à sa fin', async () => {
      const { item } = await lives.service.start('carol', { title: 'Concert' });
      const id = await open('alice', 'bob');
      const sent = await service.sendMessage('alice', id, { liveId: item.live.id });
      expect(sent.message).toMatchObject({ content: '', liveId: item.live.id });
      expect(sent.sharedLive?.item).toMatchObject({ live: { id: item.live.id, title: 'Concert', status: 'live' }, host: { id: 'carol' } });
      expect(events.pushes.at(-1)).toMatchObject({ recipientId: 'bob' });

      await lives.service.stop('carol', item.live.id);
      const [received] = (await service.listMessages('bob', id, null, 10)).items;
      expect(received.sharedLive?.item?.live.status).toBe('ended');
      await expect(service.sendMessage('alice', id, { liveId: item.live.id })).rejects.toBeInstanceOf(SharedLiveNotFoundError);
      await expect(service.sendMessage('alice', id, { liveId: '00000000-0000-7000-8000-000000000999' })).rejects.toBeInstanceOf(
        SharedLiveNotFoundError,
      );
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
      expect((await videoRepository.findPublishedByIds([video]))[0].sharesCount).toBe(1);
      await expect(service.sendMessage('alice', id, { content: 'regarde', videoId: video })).resolves.toMatchObject({
        message: { content: 'regarde' },
      });
      expect(events.pushes.map((p) => p.content)).toEqual(['', 'regarde']);
    });

    it('refuse une vidéo inconnue ; une vidéo supprimée depuis devient indisponible', async () => {
      const id = await open('alice', 'bob');
      await expect(service.sendMessage('alice', id, { videoId: 'inconnue' })).rejects.toBeInstanceOf(SharedVideoNotFoundError);

      const video = await publishedVideo('carol');
      await service.sendMessage('alice', id, { videoId: video });
      await videoRepository.delete(video);
      const [item] = (await service.listMessages('bob', id, null, 10)).items;
      expect(item.sharedVideo).toEqual({ id: video, video: null, author: null });
    });

    it("vidéo d'un compte bloqué : refusée à l'envoi, indisponible pour le destinataire concerné", async () => {
      const video = await publishedVideo('carol');
      const id = await open('alice', 'bob');
      await interactions.setBlock('carol', 'bob', true);
      await service.sendMessage('alice', id, { videoId: video });

      const shared = (viewer: string) => events.created.find((c) => c.recipientId === viewer)!.item.sharedVideo;
      expect(shared('alice')).toMatchObject({ id: video, video: { id: video }, author: { id: 'carol' } });
      expect(shared('bob')).toEqual({ id: video, video: null, author: null });
      expect((await service.listMessages('bob', id, null, 10)).items[0].sharedVideo).toEqual({ id: video, video: null, author: null });
      expect((await service.listMessages('alice', id, null, 10)).items[0].sharedVideo).toMatchObject({ author: { id: 'carol' } });
      expect((await service.listConversations('bob', null, 10)).items[0].lastMessage!.sharedVideo).toMatchObject({ video: null });

      await expect(service.sendMessage('bob', id, { videoId: video })).rejects.toBeInstanceOf(SharedVideoNotFoundError);
    });
  });

  describe('limites d’envoi', () => {
    it(`${MESSAGE_RATE_LIMITS[0].limit} messages par minute, puis 429 jusqu’à la minute suivante`, async () => {
      const id = await open('alice', 'bob');
      for (let i = 0; i < MESSAGE_RATE_LIMITS[0].limit; i++) await send('alice', id, `m${i}`);
      const refused = await send('alice', id, 'de trop').catch((error: unknown) => error);
      expect(refused).toBeInstanceOf(RateLimitedError);
      expect((refused as RateLimitedError).retryAfterSeconds).toBe(60);
      // Chaque compte a ses propres limites.
      await expect(send('bob', id, 'moi je peux')).resolves.toBeDefined();

      clock += 60_000;
      await expect(send('alice', id, 'de nouveau')).resolves.toBeDefined();
    });

    it(`${REQUEST_RATE_LIMITS[0].limit} nouvelles demandes par jour`, async () => {
      const limit = REQUEST_RATE_LIMITS[0].limit;
      for (const target of EXTRA_USERS.slice(0, limit)) await send('carol', await open('carol', target), 'salut');
      const next = await open('carol', EXTRA_USERS[limit]);
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
      expect(eventsOf('typing')).toEqual([
        ['bob', 'alice'],
        ['bob', 'alice'],
      ]);

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
      expect(first.items.map((i) => [i.participant?.id, i.lastMessage?.message.content])).toEqual([['bob', 'b2']]);
      expect(second.items.map((i) => [i.participant?.id, i.lastMessage?.message.content])).toEqual([['carol', 'c1']]);
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

  describe('chats de groupe (ADR-059)', () => {
    // alice est amie de bob (beforeEach), de carol et de u1.
    beforeEach(async () => {
      await befriend('alice', 'carol');
      await befriend('alice', 'u1');
    });
    const createGroup = async (name?: string) => (await service.createGroup('alice', { userIds: ['bob', 'carol'], name })).conversation.id;
    const contents = async (userId: string, id: string) =>
      (await service.listMessages(userId, id, null, 50)).items.map((i) => i.message.event ?? i.message.content).reverse();

    it('crée un groupe d’amis, le créateur administrateur, avec la ligne « a créé le groupe » annoncée à tous', async () => {
      const created = await service.createGroup('alice', { userIds: ['bob', 'carol', 'bob'], name: '  Les amis  ' });
      expect(created.participant).toBeNull();
      expect(created.group).toMatchObject({ name: 'Les amis', adminId: 'alice', muted: false });
      expect(created.group!.members.map((m) => m.user.id)).toEqual(['alice', 'bob', 'carol']);
      expect(await contents('bob', created.conversation.id)).toEqual(['created']);
      expect(
        eventsOf('messageCreated')
          .map(([r]) => r)
          .sort(),
      ).toEqual(['alice', 'bob', 'carol']);
      expect(events.pushes).toEqual([]);
      // Une ligne d'événement n'est jamais non lue.
      expect((await service.badges('bob')).unreadConversations).toBe(0);
      // Le groupe est dans la boîte de réception de chacun.
      expect((await service.listConversations('carol', null, 20)).items.map((i) => i.conversation.kind)).toEqual(['group']);
    });

    it('refuse moins de 2 amis, plus de 32 membres, un nom trop long et un compte qui n’est pas un ami', async () => {
      await expect(service.createGroup('alice', { userIds: ['bob'] })).rejects.toBeInstanceOf(InvalidGroupError);
      await expect(service.createGroup('alice', { userIds: ['bob', 'carol'], name: 'x'.repeat(51) })).rejects.toBeInstanceOf(InvalidGroupError);
      const many = Array.from({ length: MAX_GROUP_MEMBERS }, (_, i) => `x${i}`);
      await expect(service.createGroup('alice', { userIds: many })).rejects.toBeInstanceOf(InvalidGroupError);
      // u2 suit alice sans être suivi en retour : pas un ami.
      await interactions.setFollow('u2', 'alice', true);
      await expect(service.createGroup('alice', { userIds: ['bob', 'u2'] })).rejects.toBeInstanceOf(NotAFriendError);
      // Ami suspendu, ou bloqué : pas un ami non plus.
      await suspended.add('carol');
      await expect(service.createGroup('alice', { userIds: ['bob', 'carol'] })).rejects.toBeInstanceOf(NotAFriendError);
    });

    it('limite les créations de groupes par jour', async () => {
      const { limit } = GROUP_CREATE_RATE_LIMITS[0];
      for (let i = 0; i < limit; i++) await createGroup();
      await expect(createGroup()).rejects.toBeInstanceOf(RateLimitedError);
    });

    it('remet un message à tous les membres, avec son expéditeur, et envoie un push sauf à ceux qui ont mis le groupe en sourdine', async () => {
      const id = await createGroup('Sortie');
      await service.setGroupMuted('carol', id, true);
      events.events.length = 0;
      const sent = await send('bob', id, 'Salut tout le monde');
      expect(sent.sender?.id).toBe('bob');
      expect(
        eventsOf('messageCreated')
          .map(([r]) => r)
          .sort(),
      ).toEqual(['alice', 'bob', 'carol']);
      expect(events.pushes).toEqual([
        { recipientId: 'alice', senderId: 'bob', content: 'Salut tout le monde', asRequest: false, groupTitle: 'Sortie' },
      ]);
      expect((await service.getConversation('carol', id)).group!.muted).toBe(true);
      expect((await service.getConversation('carol', id)).conversation.unreadCount).toBe(1);
      expect((await service.badges('carol')).unreadConversations).toBe(1);
      // Sans nom : les noms des autres membres en titre.
      await service.renameGroup('alice', id, '');
      events.pushes.length = 0;
      await send('carol', id, 'Coucou');
      expect(events.pushes.map((p) => [p.recipientId, p.groupTitle])).toEqual([
        ['alice', 'bob, carol'],
        ['bob', 'alice, carol'],
      ]);
    });

    it('« Vu par » : chaque membre garde son repère, annoncé à tous les membres', async () => {
      const id = await createGroup();
      const message = await send('alice', id, 'Ça va ?');
      events.events.length = 0;
      await service.markRead('bob', id, message.message.id);
      expect(
        eventsOf('conversationRead')
          .map(([r]) => r)
          .sort(),
      ).toEqual(['alice', 'bob', 'carol']);
      const members = (await service.getConversation('alice', id)).group!.members;
      expect(members.find((m) => m.user.id === 'bob')?.lastReadMessageId).toBe(message.message.id);
    });

    it('« en train d’écrire » est relayé à tous les autres membres, sauf en cas de blocage', async () => {
      const id = await createGroup();
      await interactions.setBlock('carol', 'bob', true);
      clock += 10_000;
      await service.typing('bob', id);
      expect(eventsOf('typing')).toEqual([['alice', 'bob']]);
    });

    it('un nouveau membre voit les messages à partir de son ajout ; un compte déjà membre est ignoré', async () => {
      const id = await createGroup();
      await send('bob', id, 'Avant');
      const after = await service.addGroupMembers('carol', id, []).catch(() => null);
      expect(after).not.toBeNull();
      // carol n'est pas amie de u1 : seul un ami de celui qui ajoute peut entrer.
      await expect(service.addGroupMembers('carol', id, ['u1'])).rejects.toBeInstanceOf(NotAFriendError);
      const added = await service.addGroupMembers('alice', id, ['u1', 'bob']);
      expect(added.group!.members.map((m) => m.user.id)).toEqual(['alice', 'bob', 'carol', 'u1']);
      expect(await contents('u1', id)).toEqual(['added']);
      expect(await contents('bob', id)).toEqual(['created', 'Avant', 'added']);
      const [line] = (await service.listMessages('bob', id, null, 1)).items;
      expect([line.sender?.id, line.eventUser?.id]).toEqual(['alice', 'u1']);
      expect((await service.getConversation('u1', id)).conversation.unreadCount).toBe(0);
    });

    it('refuse un ajout au-delà de 32 membres', async () => {
      const id = await createGroup();
      // Membres fictifs jusqu'à la limite (comptes absents du dépôt des comptes).
      const members = conversations.conversations.get(id)!.members;
      for (let i = members.size; i < MAX_GROUP_MEMBERS; i++) {
        members.set(`f${i}`, { userId: `f${i}`, lastReadMessageId: null, clearedUpToMessageId: null, joinedAt: new Date(clock + i), mutedAt: null });
      }
      await expect(service.addGroupMembers('alice', id, ['u1'])).rejects.toBeInstanceOf(GroupFullError);
    });

    it('seul l’administrateur retire un membre, qui perd la conversation', async () => {
      const id = await createGroup();
      await expect(service.removeGroupMember('bob', id, 'carol')).rejects.toBeInstanceOf(NotGroupAdminError);
      await expect(service.removeGroupMember('alice', id, 'alice')).rejects.toBeInstanceOf(InvalidGroupError);
      await expect(service.removeGroupMember('alice', id, 'u1')).rejects.toBeInstanceOf(GroupMemberNotFoundError);
      events.events.length = 0;
      await service.removeGroupMember('alice', id, 'carol');
      expect(eventsOf('conversationDeleted')).toEqual([['carol', id]]);
      expect(
        eventsOf('messageCreated')
          .map(([r]) => r)
          .sort(),
      ).toEqual(['alice', 'bob']);
      await expect(service.getConversation('carol', id)).rejects.toBeInstanceOf(ConversationNotFoundError);
      await expect(send('carol', id, 'Encore là ?')).rejects.toBeInstanceOf(ConversationNotFoundError);
      expect(await contents('bob', id)).toEqual(['created', 'removed']);
    });

    it('quitter : ses messages restent, le plus ancien membre restant devient administrateur, le dernier départ supprime le groupe', async () => {
      const id = await createGroup();
      await send('alice', id, 'Je pars');
      await service.leaveGroup('alice', id);
      const seen = await service.getConversation('bob', id);
      expect(seen.group!.adminId).toBe('bob');
      expect(await contents('bob', id)).toEqual(['created', 'Je pars', 'left']);
      await service.leaveGroup('bob', id);
      expect((await service.getConversation('carol', id)).group!.members.map((m) => m.user.id)).toEqual(['carol']);
      await service.leaveGroup('carol', id);
      expect(conversations.conversations.has(id)).toBe(false);
    });

    it('renommer : tout membre, ligne « renamed », nom vide retiré', async () => {
      const id = await createGroup();
      const renamed = await service.renameGroup('carol', id, ' Vacances ');
      expect(renamed.group!.name).toBe('Vacances');
      const [line] = (await service.listMessages('alice', id, null, 1)).items;
      expect([line.message.event, line.message.content]).toEqual(['renamed', 'Vacances']);
      // Même nom : rien n'est annoncé.
      events.events.length = 0;
      await service.renameGroup('alice', id, 'Vacances');
      expect(events.events).toEqual([]);
      expect((await service.renameGroup('alice', id, '')).group!.name).toBeNull();
    });

    it('masque à chacun les messages d’un membre avec qui il a un blocage, et ceux d’un compte suspendu à tous', async () => {
      const id = await createGroup();
      await interactions.setBlock('bob', 'carol', true);
      events.events.length = 0;
      await send('carol', id, 'De carol');
      expect(
        eventsOf('messageCreated')
          .map(([r]) => r)
          .sort(),
      ).toEqual(['alice', 'carol']);
      expect(await contents('bob', id)).toEqual(['created']);
      expect((await service.getConversation('bob', id)).lastMessage?.message.event).toBe('created');
      expect((await service.badges('bob')).unreadConversations).toBe(0);
      expect(await service.searchMessages('bob', 'carol', 10)).toEqual([]);
      const carolMessage = (await service.listMessages('alice', id, null, 1)).items[0].message;
      await expect(service.getVisibleMessage('bob', carolMessage.id)).rejects.toBeInstanceOf(MessageNotFoundError);
      // Toujours membres tous les deux.
      expect((await service.getConversation('bob', id)).group!.members).toHaveLength(3);
      await suspended.add('carol');
      expect(await contents('alice', id)).toEqual(['created']);
    });

    it('recherche : un message de groupe porte le groupe et son expéditeur', async () => {
      const id = await createGroup('Ciné');
      await send('bob', id, 'On va au cinéma ?');
      const [result] = await service.searchMessages('alice', 'cinéma', 10);
      expect(result.message.conversationId).toBe(id);
      expect(result.sender.id).toBe('bob');
      expect(result.group).toMatchObject({ name: 'Ciné' });
      expect(result.group!.members.map((u) => u.id)).toEqual(['alice', 'bob', 'carol']);
    });

    it('les actions de groupe sont refusées sur une conversation à deux, et un groupe n’est jamais pris pour elle', async () => {
      const direct = await open('alice', 'bob');
      await expect(service.leaveGroup('alice', direct)).rejects.toBeInstanceOf(NotAGroupError);
      await expect(service.renameGroup('alice', direct, 'x')).rejects.toBeInstanceOf(NotAGroupError);
      const id = await createGroup();
      await service.leaveGroup('carol', id);
      expect(await open('alice', 'bob')).toBe(direct);
      expect(await open('bob', 'alice')).not.toBe(id);
    });

    it('une réponse à une story n’est pas possible dans un groupe', async () => {
      const id = await createGroup();
      await expect(
        service.sendMessage('alice', id, { content: 'Belle story', storyId: '00000000-0000-0000-0000-000000000001' }),
      ).rejects.toBeInstanceOf(RepliedStoryNotFoundError);
    });

    it('suppression d’un compte : le groupe reste tant qu’il a un membre', async () => {
      const id = await createGroup();
      conversations.removeUser('alice');
      conversations.removeUser('bob');
      expect((await service.getConversation('carol', id)).group!.adminId).toBe('carol');
      conversations.removeUser('carol');
      expect(conversations.conversations.has(id)).toBe(false);
    });
  });
});
