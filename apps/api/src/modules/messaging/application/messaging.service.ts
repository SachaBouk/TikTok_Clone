import type { InteractionsService } from '../../interactions/application/interactions.service';
import type { UsersService } from '../../users/application/users.service';
import type { User } from '../../users/domain/user';
import { UserNotFoundError } from '../../users/domain/user.errors';
import type { VideosService } from '../../videos/application/videos.service';
import type { ConversationRepository } from '../domain/conversation.repository';
import type { MessagingEventPublisher } from '../domain/messaging-event-publisher';
import {
  MESSAGE_RATE_LIMITS,
  REQUEST_MESSAGE_LIMIT,
  REQUEST_RATE_LIMITS,
  TYPING_THROTTLE_MS,
  type ConversationStatus,
  type ConversationView,
  type Message,
  type MessageItem,
  type MessagingBadges,
} from '../domain/messaging';
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
import type { RateLimiter, RateLimitRule } from '../../../rate-limit/rate-limiter';

export interface ConversationWithParticipant {
  conversation: ConversationView;
  lastMessage: MessageItem | null;
  participant: User;
  status: ConversationStatus;
  canSend: boolean;
  // Messages encore possibles dans une demande envoyée ; null hors demande envoyée.
  remainingRequestMessages: number | null;
  blockedByMe: boolean;
  // Dernier message lu par l'autre (« Vu ») : seulement dans une conversation acceptée.
  participantLastReadMessageId: string | null;
}

export interface ConversationPage {
  items: ConversationWithParticipant[];
  nextCursor: string | null;
}

export interface MessagePage {
  items: MessageItem[];
  nextCursor: string | null;
}

export interface SendMessageInput {
  content?: string;
  videoId?: string;
}

// Service applicatif de la messagerie directe (ADR-016, ADR-003).
// - Conversations à deux, obtenues ou créées par pseudo ; historique réservé aux participants.
// - Abonnés mutuels ou conversation acceptée : envoi libre. Sinon, demande de message (3 messages au plus
//   avant acceptation), sans « Vu » ni « en train d'écrire ». Répondre à une demande l'accepte.
// - Blocage (interactions) : plus aucun envoi, dans les deux sens ; les demandes des comptes bloqués sont masquées.
// - Retrait d'un message par son expéditeur (pour les deux) ; suppression d'une conversation pour soi seulement.
// - Partage de vidéo (compté comme un partage) ; limites d'envoi (anti-spam).
// - Chaque changement est poussé aux appareils des participants (WebSocket, ADR-011), et un nouveau message
//   ou une nouvelle demande en notification push. Les messages n'alimentent pas le centre d'activité.
export class MessagingService {
  private readonly lastTyping = new Map<string, number>();

  constructor(
    private readonly conversations: ConversationRepository,
    private readonly users: UsersService,
    private readonly interactions: InteractionsService,
    private readonly videos: VideosService,
    private readonly events: MessagingEventPublisher,
    private readonly rateLimiter: RateLimiter,
    private readonly now: () => number = () => Date.now(),
  ) {}

  // Ouvre la conversation avec @username (écran de discussion) : l'existante, sinon une nouvelle, vide.
  // Une conversation vide n'apparaît nulle part. Possible même bloqué : l'historique reste lisible.
  async openConversation(userId: string, username: string): Promise<ConversationWithParticipant> {
    const recipient = await this.recipient(username);
    if (recipient.id === userId) throw new CannotMessageYourselfError();
    return this.getConversation(userId, await this.conversations.findOrCreateDirect(userId, recipient.id));
  }

  async getConversation(userId: string, conversationId: string): Promise<ConversationWithParticipant> {
    const view = await this.conversations.findView(conversationId, userId);
    const [item] = view ? await this.withParticipants(userId, [view]) : [];
    if (!item) throw new ConversationNotFoundError(conversationId);
    return item;
  }

  // Boîte de réception : conversations acceptées et demandes envoyées. Curseur = identifiant du dernier
  // message de la dernière conversation reçue. Une conversation qui reçoit un message pendant le scroll
  // remonte en tête : elle peut manquer aux pages suivantes, la page 1 relue (ou le WebSocket) la montre.
  async listConversations(userId: string, cursor: string | null, limit: number): Promise<ConversationPage> {
    const rows = await this.conversations.listInbox(userId, cursor, limit + 1);
    return this.page(userId, rows, limit);
  }

  // Demandes reçues en attente. Celles des comptes bloqués (dans un sens ou l'autre) sont masquées :
  // une page peut alors être plus courte, la pagination continue.
  async listRequests(userId: string, cursor: string | null, limit: number): Promise<ConversationPage> {
    const rows = await this.conversations.listRequests(userId, cursor, limit + 1);
    const page = await this.page(userId, rows, limit);
    return { ...page, items: page.items.filter((item) => item.canSend) };
  }

  // Du plus récent au plus ancien, sans les messages de la conversation supprimée pour ce compte.
  async listMessages(userId: string, conversationId: string, cursor: string | null, limit: number): Promise<MessagePage> {
    const member = await this.member(conversationId, userId);
    const rows = await this.conversations.listMessages(conversationId, cursor, member.clearedUpToMessageId, limit + 1);
    const page = rows.slice(0, limit);
    return { items: await this.withVideos(userId, page), nextCursor: rows.length > limit ? page.at(-1)!.id : null };
  }

  async sendMessage(userId: string, conversationId: string, input: SendMessageInput): Promise<MessageItem> {
    const content = input.content?.trim() ?? '';
    const sharedVideoId = input.videoId ?? null;
    if (!content && !sharedVideoId) throw new EmptyMessageError();

    const view = await this.conversations.findView(conversationId, userId);
    if (!view) throw new ConversationNotFoundError(conversationId);
    const otherId = view.participantId;
    const blocks = await this.interactions.getBlocks(userId, [otherId]);
    if (blocks.blockedByMe.size > 0 || blocks.blockedMe.size > 0) throw new BlockedConversationError();
    const mutual = (await this.interactions.getMutualFollowers(userId, [otherId])).has(otherId);

    const status = this.status(view, mutual);
    if (status === 'requestSent' && view.ownMessageCount >= REQUEST_MESSAGE_LIMIT) throw new RequestLimitReachedError(REQUEST_MESSAGE_LIMIT);
    // Répondre à une demande l'accepte ; entre abonnés mutuels, la conversation est acceptée d'emblée.
    const accept = !view.accepted && status !== 'requestSent';
    const openRequest = status === 'requestSent' && view.requestSenderId === null;
    // Vidéo introuvable aussi quand son auteur et l'expéditeur se sont bloqués : l'expéditeur ne la voit pas.
    if (sharedVideoId) {
      const [video] = await this.videos.getPublishedVideos([sharedVideoId]);
      if (!video || (await this.interactions.getBlockedAccountIds(userId)).has(video.userId)) throw new SharedVideoNotFoundError(sharedVideoId);
    }

    if (openRequest) await this.limit(`request:${userId}`, REQUEST_RATE_LIMITS);
    await this.limit(`message:${userId}`, MESSAGE_RATE_LIMITS);

    const message = await this.conversations.addMessage({ conversationId, senderId: userId, content, sharedVideoId, accept, openRequest });
    if (sharedVideoId) await this.videos.recordShare(sharedVideoId);
    const [item] = await this.withVideos(userId, [message]);

    // Demande refusée : ses messages suivants ne sont plus remis au destinataire (l'expéditeur n'en sait rien).
    // La vidéo partagée est vue par chacun (indisponible pour celui qui a un blocage avec son auteur).
    const recipients = view.declined && !accept ? [userId] : [userId, otherId];
    const received = recipients.includes(otherId) ? (await this.withVideos(otherId, [message]))[0]! : null;
    for (const recipientId of recipients) {
      await this.events.messageCreated(recipientId, recipientId === userId ? item! : received!, await this.badges(recipientId));
    }
    if (accept && view.requestSenderId !== null) {
      for (const recipientId of [userId, otherId]) await this.events.conversationAccepted(recipientId, conversationId, await this.badges(recipientId));
    }
    if (received) await this.events.pushNewMessage(otherId, await this.users.getById(userId), received, status === 'requestSent');
    return item!;
  }

  // Retrait par l'expéditeur, pour les deux participants, sans limite de temps.
  async deleteMessage(userId: string, messageId: string): Promise<void> {
    const message = await this.conversations.findMessage(messageId);
    const conversation = message && (await this.conversations.findConversation(message.conversationId));
    if (!message || !conversation?.members.some((m) => m.userId === userId)) throw new MessageNotFoundError(messageId);
    if (message.senderId !== userId) throw new NotMessageSenderError();

    await this.conversations.deleteMessage(messageId);
    const delivered = !conversation.declinedAt || conversation.acceptedAt !== null;
    for (const { userId: recipientId } of conversation.members) {
      if (recipientId !== userId && !delivered) continue;
      await this.events.messageDeleted(recipientId, { conversationId: message.conversationId, messageId }, await this.badges(recipientId));
    }
  }

  // Supprime la conversation pour soi : l'historique disparaît, elle réapparaît au prochain message.
  // L'autre participant garde tout.
  async deleteConversation(userId: string, conversationId: string): Promise<void> {
    await this.member(conversationId, userId);
    await this.conversations.clearFor(conversationId, userId);
    await this.events.conversationDeleted(userId, conversationId, await this.badges(userId));
  }

  async acceptRequest(userId: string, conversationId: string): Promise<ConversationWithParticipant> {
    const view = await this.pendingRequest(userId, conversationId);
    await this.conversations.accept(conversationId);
    for (const recipientId of [userId, view.participantId]) {
      await this.events.conversationAccepted(recipientId, conversationId, await this.badges(recipientId));
    }
    return this.getConversation(userId, conversationId);
  }

  // Refus : la demande disparaît chez le destinataire, et ses messages suivants ne lui sont plus remis.
  // L'expéditeur n'est pas prévenu.
  async declineRequest(userId: string, conversationId: string): Promise<void> {
    await this.pendingRequest(userId, conversationId);
    await this.conversations.decline(conversationId);
    await this.conversations.clearFor(conversationId, userId);
    await this.events.conversationDeleted(userId, conversationId, await this.badges(userId));
  }

  // À l'affichage de la conversation : l'app envoie le message le plus récent qu'elle montre (sans `upToId` :
  // tout). « Vu » n'est envoyé à l'autre que dans une conversation acceptée. Renvoie les badges.
  async markRead(userId: string, conversationId: string, upToId: string | null): Promise<MessagingBadges> {
    const view = await this.conversations.findView(conversationId, userId);
    if (!view) throw new ConversationNotFoundError(conversationId);
    const lastReadMessageId = await this.conversations.markRead(conversationId, userId, upToId);
    if (lastReadMessageId) {
      const read = { conversationId, readerId: userId, lastReadMessageId };
      for (const recipientId of view.accepted ? [userId, view.participantId] : [userId]) {
        await this.events.conversationRead(recipientId, read, await this.badges(recipientId));
      }
    }
    return this.badges(userId);
  }

  // « En train d'écrire » (message WebSocket de l'app) : relayé à l'autre participant, au plus un par
  // TYPING_THROTTLE_MS, seulement dans une conversation libre et sans blocage. Jamais d'erreur : sans effet sinon.
  async typing(userId: string, conversationId: string): Promise<void> {
    const key = `${userId}:${conversationId}`;
    const now = this.now();
    if (now - (this.lastTyping.get(key) ?? 0) < TYPING_THROTTLE_MS) return;
    this.lastTyping.set(key, now);
    if (this.lastTyping.size > 10_000) {
      for (const [k, at] of this.lastTyping) if (now - at >= TYPING_THROTTLE_MS) this.lastTyping.delete(k);
    }

    const view = await this.conversations.findView(conversationId, userId);
    if (!view) return;
    const otherId = view.participantId;
    const blocks = await this.interactions.getBlocks(userId, [otherId]);
    if (blocks.blockedByMe.size > 0 || blocks.blockedMe.size > 0) return;
    const free = view.accepted || (view.requestSenderId === null && (await this.interactions.getMutualFollowers(userId, [otherId])).has(otherId));
    if (free) await this.events.typing(otherId, { conversationId, userId });
  }

  async badges(userId: string): Promise<MessagingBadges> {
    const senders = await this.conversations.listPendingRequestSenders(userId);
    const blocks = await this.interactions.getBlocks(userId, senders);
    return {
      unreadConversations: await this.conversations.countUnreadConversations(userId),
      pendingRequests: senders.filter((id) => !blocks.blockedByMe.has(id) && !blocks.blockedMe.has(id)).length,
    };
  }

  private status(view: ConversationView, mutual: boolean): ConversationStatus {
    if (view.accepted) return 'direct';
    if (view.requestSenderId === view.participantId) return 'requestReceived';
    return mutual ? 'direct' : 'requestSent';
  }

  private async pendingRequest(userId: string, conversationId: string): Promise<ConversationView> {
    const view = await this.conversations.findView(conversationId, userId);
    if (!view) throw new ConversationNotFoundError(conversationId);
    if (view.accepted || view.requestSenderId !== view.participantId) throw new NotAPendingRequestError();
    return view;
  }

  private async member(conversationId: string, userId: string) {
    const member = (await this.conversations.findConversation(conversationId))?.members.find((m) => m.userId === userId);
    if (!member) throw new ConversationNotFoundError(conversationId);
    return member;
  }

  private async limit(key: string, rules: RateLimitRule[]): Promise<void> {
    const retryAfter = await this.rateLimiter.consume(key, rules);
    if (retryAfter !== null) throw new RateLimitedError(retryAfter);
  }

  private async recipient(username: string): Promise<User> {
    try {
      return await this.users.getByUsername(username);
    } catch (error) {
      if (error instanceof UserNotFoundError) throw new RecipientNotFoundError(username);
      throw error;
    }
  }

  private async page(userId: string, rows: ConversationView[], limit: number): Promise<ConversationPage> {
    const page = rows.slice(0, limit);
    return { items: await this.withParticipants(userId, page), nextCursor: rows.length > limit ? page.at(-1)!.lastMessage!.id : null };
  }

  // Autres participants (users), follows mutuels et blocages (interactions), vidéos partagées (videos) :
  // lus par les services exportés, jamais par leurs tables (ADR-003).
  private async withParticipants(userId: string, views: ConversationView[]): Promise<ConversationWithParticipant[]> {
    const ids = views.map((v) => v.participantId);
    const participants = new Map((await this.users.getByIds(ids)).map((u) => [u.id, u]));
    const mutual = await this.interactions.getMutualFollowers(userId, ids);
    const blocks = await this.interactions.getBlocks(userId, ids);
    const lastMessages = new Map(
      (await this.withVideos(userId, views.flatMap((v) => (v.lastMessage ? [v.lastMessage] : [])))).map((item) => [item.message.conversationId, item]),
    );
    return views.flatMap((conversation) => {
      const participant = participants.get(conversation.participantId);
      if (!participant) return [];
      const status = this.status(conversation, mutual.has(participant.id));
      const blocked = blocks.blockedByMe.has(participant.id) || blocks.blockedMe.has(participant.id);
      const remaining = status === 'requestSent' ? Math.max(0, REQUEST_MESSAGE_LIMIT - conversation.ownMessageCount) : null;
      return [
        {
          conversation,
          lastMessage: lastMessages.get(conversation.id) ?? null,
          participant,
          status,
          canSend: !blocked && remaining !== 0,
          remainingRequestMessages: remaining,
          blockedByMe: blocks.blockedByMe.has(participant.id),
          participantLastReadMessageId: conversation.accepted ? conversation.participantLastReadMessageId : null,
        },
      ];
    });
  }

  // Vidéos partagées, telles que `viewerId` les voit : celle d'un compte bloqué dans un sens ou dans l'autre
  // est indisponible, comme dans le feed (blocages lus seulement s'il y a des vidéos).
  private async withVideos(viewerId: string, messages: Message[]): Promise<MessageItem[]> {
    const videoIds = [...new Set(messages.flatMap((m) => (m.sharedVideoId ? [m.sharedVideoId] : [])))];
    const [published, hidden] = videoIds.length
      ? await Promise.all([this.videos.getPublishedVideos(videoIds), this.interactions.getBlockedAccountIds(viewerId)])
      : [[], new Set<string>()];
    const videos = new Map(published.filter((v) => !hidden.has(v.userId)).map((v) => [v.id, v]));
    const authors = new Map((await this.users.getByIds([...videos.values()].map((v) => v.userId))).map((u) => [u.id, u]));
    return messages.map((message) => {
      if (!message.sharedVideoId) return { message, sharedVideo: null };
      const video = videos.get(message.sharedVideoId) ?? null;
      const author = video ? (authors.get(video.userId) ?? null) : null;
      // Vidéo supprimée, son auteur, ou compte bloqué : « indisponible ».
      return { message, sharedVideo: { id: message.sharedVideoId, video: author ? video : null, author } };
    });
  }
}
