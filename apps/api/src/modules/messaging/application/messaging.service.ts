import type { InteractionsService } from '../../interactions/application/interactions.service';
import type { LiveItem, LiveService } from '../../live/application/live.service';
import { LiveNotFoundError } from '../../live/domain/live.errors';
import type { StoriesService } from '../../stories/application/stories.service';
import type { ActiveStory } from '../../stories/domain/story';
import { StoryNotFoundError } from '../../stories/domain/story.errors';
import type { UsersService } from '../../users/application/users.service';
import type { User } from '../../users/domain/user';
import { UserNotFoundError } from '../../users/domain/user.errors';
import type { VideosService } from '../../videos/application/videos.service';
import type { ConversationRepository } from '../domain/conversation.repository';
import type { MessagingEventPublisher } from '../domain/messaging-event-publisher';
import {
  GROUP_CREATE_RATE_LIMITS,
  groupAdminId,
  MAX_GROUP_MEMBERS,
  MAX_GROUP_NAME_LENGTH,
  MESSAGE_RATE_LIMITS,
  MIN_GROUP_FRIENDS,
  REQUEST_MESSAGE_LIMIT,
  REQUEST_RATE_LIMITS,
  TYPING_THROTTLE_MS,
  type Conversation,
  type ConversationMember,
  type ConversationStatus,
  type ConversationView,
  type Message,
  type MessageItem,
  type MessagingBadges,
} from '../domain/messaging';
import {
  BlockedConversationError,
  CannotMessageYourselfError,
  ClientMessageIdConflictError,
  ConversationNotFoundError,
  EmptyMessageError,
  GroupFullError,
  GroupMemberNotFoundError,
  InvalidGroupError,
  MessageNotFoundError,
  NotAFriendError,
  NotAGroupError,
  NotGroupAdminError,
  NotAPendingRequestError,
  NotMessageSenderError,
  RateLimitedError,
  RecipientNotFoundError,
  RepliedStoryNotFoundError,
  SharedLiveNotFoundError,
  RequestLimitReachedError,
  SharedVideoNotFoundError,
} from '../domain/messaging.errors';
import type { RateLimiter, RateLimitRule } from '../../../rate-limit/rate-limiter';

// Membre d'un groupe (ADR-059), vu par un autre membre.
export interface GroupMember {
  user: User;
  joinedAt: Date;
  // Dernier message lu (« Vu par »).
  lastReadMessageId: string | null;
}

export interface GroupInfo {
  name: string | null;
  // Le membre le plus ancien.
  adminId: string;
  // Sourdine du lecteur.
  muted: boolean;
  // Du plus ancien au plus récent ; un compte supprimé n'y est plus.
  members: GroupMember[];
}

export interface ConversationWithParticipant {
  conversation: ConversationView;
  lastMessage: MessageItem | null;
  // L'autre participant ; null pour un groupe.
  participant: User | null;
  group: GroupInfo | null;
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

// Message trouvé par la recherche (ADR-058), avec l'autre participant de sa conversation (ou son groupe) et son expéditeur.
export interface MessageSearchResult {
  message: Message;
  // Conversation à deux : l'autre participant ; groupe : l'expéditeur.
  participant: User;
  sender: User;
  group: { name: string | null; members: User[] } | null;
}

export interface CreateGroupInput {
  userIds: string[];
  name?: string | null;
}

export interface SendMessageInput {
  content?: string;
  videoId?: string;
  // Story de l'autre participant à laquelle répond le message (ADR-051) ; un texte est alors obligatoire.
  storyId?: string;
  // Live en cours partagé (ADR-053).
  liveId?: string;
  // Identifiant d'envoi choisi par l'app (ADR-044) : renvoyer le même rend le message déjà créé.
  clientMessageId?: string;
}

// Service applicatif de la messagerie directe (ADR-016, ADR-003).
// - Conversations à deux, obtenues ou créées par pseudo ; historique réservé aux participants.
// - Abonnés mutuels ou conversation acceptée : envoi libre. Sinon, demande de message (3 messages au plus
//   avant acceptation), sans « Vu » ni « en train d'écrire ». Répondre à une demande l'accepte.
// - Blocage (interactions) : plus aucun envoi, dans les deux sens ; les demandes des comptes bloqués sont masquées.
// - Retrait d'un message par son expéditeur (pour les deux) ; suppression d'une conversation pour soi seulement.
// - Partage de vidéo (compté comme un partage), réponse à une story (ADR-051) ; limites d'envoi (anti-spam).
// - Chats de groupe (ADR-059) : privés, 32 membres, amis seulement, administrateur = membre le plus ancien, lignes
//   d'événement ; messages des comptes masqués au lecteur (blocage, suspension) cachés ; sourdine par membre.
// - Chaque changement est poussé aux appareils des participants (WebSocket, ADR-011), et un nouveau message
//   ou une nouvelle demande en notification push. Les messages n'alimentent pas le centre d'activité.
export class MessagingService {
  private readonly lastTyping = new Map<string, number>();

  constructor(
    private readonly conversations: ConversationRepository,
    private readonly users: UsersService,
    private readonly interactions: InteractionsService,
    private readonly videos: VideosService,
    private readonly stories: StoriesService,
    private readonly lives: LiveService,
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
    const view = await this.conversations.findView(conversationId, userId, await this.hiddenIds(userId));
    const [item] = view ? await this.withParticipants(userId, [view]) : [];
    if (!item) throw new ConversationNotFoundError(conversationId);
    return item;
  }

  // Boîte de réception : conversations acceptées et demandes envoyées. Curseur = identifiant du dernier
  // message de la dernière conversation reçue. Une conversation qui reçoit un message pendant le scroll
  // remonte en tête : elle peut manquer aux pages suivantes, la page 1 relue (ou le WebSocket) la montre.
  async listConversations(userId: string, cursor: string | null, limit: number): Promise<ConversationPage> {
    const rows = await this.conversations.listInbox(userId, cursor, limit + 1, await this.hiddenIds(userId));
    return this.page(userId, rows, limit);
  }

  // Demandes reçues en attente. Celles des comptes bloqués (dans un sens ou l'autre) ou suspendus sont masquées :
  // une page peut alors être plus courte, la pagination continue.
  async listRequests(userId: string, cursor: string | null, limit: number): Promise<ConversationPage> {
    const rows = await this.conversations.listRequests(userId, cursor, limit + 1);
    const page = await this.page(userId, rows, limit);
    return { ...page, items: page.items.filter((item) => item.canSend) };
  }

  // Recherche dans le texte de ses messages (ADR-058) : ses conversations seulement, sans les messages supprimés pour
  // lui ni les demandes reçues qu'il a refusées ; une demande reçue en attente d'un compte masqué (bloqué, suspendu) est
  // sautée, comme dans la liste des demandes. Du plus récent au plus ancien.
  async searchMessages(userId: string, query: string, limit: number): Promise<MessageSearchResult[]> {
    const text = query.trim();
    if (!text) return [];
    const hidden = await this.interactions.getHiddenAccountIds(userId);
    const messages = await this.conversations.searchMessages(userId, text, limit, [...hidden]);
    if (messages.length === 0) return [];
    const conversationIds = [...new Set(messages.map((m) => m.conversationId))];
    const conversations = new Map(
      (await Promise.all(conversationIds.map((id) => this.conversations.findConversation(id)))).flatMap((c) => (c ? [[c.id, c] as const] : [])),
    );
    const memberIds = [...conversations.values()].flatMap((c) => c.members.map((m) => m.userId));
    const byId = new Map((await this.users.getByIds([...new Set([userId, ...memberIds, ...messages.map((m) => m.senderId)])])).map((u) => [u.id, u]));
    return messages.flatMap((message): MessageSearchResult[] => {
      const conversation = conversations.get(message.conversationId);
      const sender = byId.get(message.senderId);
      if (!conversation || !sender) return [];
      if (conversation.kind === 'group') {
        const members = this.sortedMembers(conversation.members).flatMap((m) => byId.get(m.userId) ?? []);
        return [{ message, participant: sender, sender, group: { name: conversation.name, members } }];
      }
      const participant = byId.get(conversation.members.find((m) => m.userId !== userId)?.userId ?? '');
      if (!participant) return [];
      const pendingReceived = !conversation.acceptedAt && !conversation.declinedAt && conversation.requestSenderId === participant.id;
      if (pendingReceived && hidden.has(participant.id)) return [];
      return [{ message, participant, sender, group: null }];
    });
  }

  // Du plus récent au plus ancien, sans les messages de la conversation supprimée pour ce compte.
  async listMessages(userId: string, conversationId: string, cursor: string | null, limit: number): Promise<MessagePage> {
    const conversation = await this.conversations.findConversation(conversationId);
    const member = conversation?.members.find((m) => m.userId === userId);
    if (!conversation || !member) throw new ConversationNotFoundError(conversationId);
    const rows = await this.conversations.listMessages(conversationId, cursor, member.clearedUpToMessageId, limit + 1);
    const page = rows.slice(0, limit);
    const nextCursor = rows.length > limit ? page.at(-1)!.id : null;
    if (conversation.kind === 'direct') return { items: await this.withVideos(userId, page), nextCursor };
    // Groupe : messages des comptes masqués au lecteur retirés (page plus courte, curseur inchangé).
    const hidden = await this.interactions.getHiddenAccountIds(userId);
    return {
      items: await this.withVideos(
        userId,
        page.filter((m) => !hidden.has(m.senderId)),
        true,
      ),
      nextCursor,
    };
  }

  async sendMessage(userId: string, conversationId: string, input: SendMessageInput): Promise<MessageItem> {
    const content = input.content?.trim() ?? '';
    const sharedVideoId = input.videoId ?? null;
    const storyId = input.storyId ?? null;
    const liveId = input.liveId ?? null;
    // Réponse à une story : texte obligatoire. Sinon : texte, vidéo ou live partagé.
    if (storyId ? !content : !content && !sharedVideoId && !liveId) throw new EmptyMessageError();

    const view = await this.conversations.findView(conversationId, userId);
    if (!view) throw new ConversationNotFoundError(conversationId);
    // Renvoi d'un envoi déjà enregistré (réponse perdue, ADR-044) : le message existant, sans contrôle ni limite ni
    // événement, même si la conversation ne permet plus d'écrire (il était parti avant).
    const clientMessageId = input.clientMessageId ?? null;
    const sent = clientMessageId ? await this.conversations.findByClientMessageId(userId, clientMessageId) : null;
    if (sent) return this.alreadySent(userId, conversationId, sent, clientMessageId!);
    // Groupe (ADR-059) : envoi libre pour tout membre ; une réponse à une story reste dans la conversation avec son auteur.
    const group = view.kind === 'group';
    if (group && storyId) throw new RepliedStoryNotFoundError(storyId);
    const otherId = view.participantId ?? '';
    let status: ConversationStatus = 'direct';
    if (!group) {
      const blocks = await this.interactions.getBlocks(userId, [otherId]);
      if (blocks.blockedByMe.size > 0 || blocks.blockedMe.size > 0) throw new BlockedConversationError();
      status = this.status(view, (await this.interactions.getMutualFollowers(userId, [otherId])).has(otherId));
    }
    if (status === 'requestSent' && view.ownMessageCount >= REQUEST_MESSAGE_LIMIT) throw new RequestLimitReachedError(REQUEST_MESSAGE_LIMIT);
    // Répondre à une demande l'accepte ; entre abonnés mutuels, la conversation est acceptée d'emblée.
    const accept = !view.accepted && status !== 'requestSent';
    const openRequest = status === 'requestSent' && view.requestSenderId === null;
    // Vidéo introuvable aussi quand son auteur et l'expéditeur se sont bloqués : l'expéditeur ne la voit pas.
    if (sharedVideoId) {
      const [video] = await this.videos.getPublishedVideos([sharedVideoId], userId);
      if (!video || (await this.interactions.getHiddenAccountIds(userId)).has(video.userId)) throw new SharedVideoNotFoundError(sharedVideoId);
    }
    // Réponse à une story : visible de l'expéditeur (active, pas d'un compte masqué) et publiée par l'autre participant.
    if (storyId) {
      const story = await this.stories.getVisibleStory(userId, storyId).catch((error: unknown) => {
        if (error instanceof StoryNotFoundError) throw new RepliedStoryNotFoundError(storyId);
        throw error;
      });
      if (story.userId !== otherId) throw new RepliedStoryNotFoundError(storyId);
    }

    // Live partagé : en cours, visible de l'expéditeur.
    if (liveId) {
      await this.lives.getVisibleLive(userId, liveId).catch((error: unknown) => {
        if (error instanceof LiveNotFoundError) throw new SharedLiveNotFoundError(liveId);
        throw error;
      });
    }

    if (openRequest) await this.limit(`request:${userId}`, REQUEST_RATE_LIMITS);
    await this.limit(`message:${userId}`, MESSAGE_RATE_LIMITS);

    const message = await this.conversations.addMessage({
      conversationId,
      senderId: userId,
      content,
      sharedVideoId,
      storyId,
      liveId,
      clientMessageId,
      accept,
      openRequest,
    });
    if (!message) {
      // Même identifiant enregistré entre-temps par un envoi simultané : c'est lui qui annonce le message.
      const concurrent = await this.conversations.findByClientMessageId(userId, clientMessageId!);
      if (!concurrent) throw new ClientMessageIdConflictError();
      return this.alreadySent(userId, conversationId, concurrent, clientMessageId!);
    }
    if (sharedVideoId) await this.videos.recordShare(sharedVideoId);
    const [item] = await this.withVideos(userId, [message], group);
    if (clientMessageId) item.clientMessageId = clientMessageId;
    if (group) {
      await this.deliverToGroup(conversationId, message, item, true);
      return item;
    }

    // Demande refusée : ses messages suivants ne sont plus remis au destinataire (l'expéditeur n'en sait rien).
    // La vidéo partagée est vue par chacun (indisponible pour celui qui a un blocage avec son auteur).
    const recipients = view.declined && !accept ? [userId] : [userId, otherId];
    const received = recipients.includes(otherId) ? (await this.withVideos(otherId, [message]))[0] : null;
    for (const recipientId of recipients) {
      await this.events.messageCreated(recipientId, recipientId === userId ? item : received!, await this.badges(recipientId));
    }
    if (accept && view.requestSenderId !== null) {
      for (const recipientId of [userId, otherId])
        await this.events.conversationAccepted(recipientId, conversationId, await this.badges(recipientId));
    }
    if (received) await this.events.pushNewMessage(otherId, await this.users.getById(userId), received, status === 'requestSent');
    return item;
  }

  private async alreadySent(userId: string, conversationId: string, message: Message, clientMessageId: string): Promise<MessageItem> {
    if (message.conversationId !== conversationId) throw new ClientMessageIdConflictError();
    const conversation = await this.conversations.findConversation(conversationId);
    const [item] = await this.withVideos(userId, [message], conversation?.kind === 'group');
    return { ...item, clientMessageId };
  }

  // Retrait par l'expéditeur, pour les deux participants, sans limite de temps.
  async deleteMessage(userId: string, messageId: string): Promise<void> {
    const message = await this.conversations.findMessage(messageId);
    const conversation = message && (await this.conversations.findConversation(message.conversationId));
    if (!message || !conversation?.members.some((m) => m.userId === userId)) throw new MessageNotFoundError(messageId);
    if (message.senderId !== userId) throw new NotMessageSenderError();
    await this.retract(message, conversation);
  }

  // Pour le module reports (ADR-038) : un message que `userId` voit (participant, pas supprimé pour lui).
  async getVisibleMessage(userId: string, messageId: string): Promise<Message> {
    const message = await this.conversations.findMessage(messageId);
    const conversation = message && (await this.conversations.findConversation(message.conversationId));
    const member = conversation?.members.find((m) => m.userId === userId);
    if (!message || !member || message.event || (member.clearedUpToMessageId !== null && message.id <= member.clearedUpToMessageId)) {
      throw new MessageNotFoundError(messageId);
    }
    // Groupe : le message d'un compte masqué au lecteur ne lui est pas montré (ADR-059).
    if (conversation?.kind === 'group' && (await this.interactions.getHiddenAccountIds(userId)).has(message.senderId)) {
      throw new MessageNotFoundError(messageId);
    }
    return message;
  }

  // Pour le module admin (file des signalements) : messages existants parmi `ids`.
  getMessages(ids: string[]): Promise<Message[]> {
    return this.conversations.findMessagesByIds([...new Set(ids)]);
  }

  // Retrait par un administrateur (ADR-038), comme par son expéditeur : pour les deux participants. Renvoie le message.
  async removeMessage(messageId: string): Promise<Message> {
    const message = await this.conversations.findMessage(messageId);
    const conversation = message && (await this.conversations.findConversation(message.conversationId));
    if (!message || !conversation) throw new MessageNotFoundError(messageId);
    await this.retract(message, conversation);
    return message;
  }

  // Suppression pour les deux, annoncée aux participants (pas à celui qui a refusé la demande, qui ne la voyait pas).
  private async retract(message: Message, conversation: Conversation): Promise<void> {
    await this.conversations.deleteMessage(message.id);
    const delivered = !conversation.declinedAt || conversation.acceptedAt !== null;
    for (const { userId: recipientId } of conversation.members) {
      if (recipientId !== message.senderId && !delivered) continue;
      await this.events.messageDeleted(
        recipientId,
        { conversationId: message.conversationId, messageId: message.id },
        await this.badges(recipientId),
      );
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
    for (const recipientId of [userId, view.participantId!]) {
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
      const others = view.kind === 'group' ? await this.otherMembers(conversationId, userId) : view.accepted ? [view.participantId!] : [];
      for (const recipientId of [userId, ...others]) {
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
    if (view.kind === 'group') {
      // Groupe : à chaque autre membre, sauf ceux qui ont un blocage avec lui (ADR-059).
      for (const recipientId of await this.deliverable(userId, await this.otherMembers(conversationId, userId))) {
        await this.events.typing(recipientId, { conversationId, userId });
      }
      return;
    }
    const otherId = view.participantId!;
    const blocks = await this.interactions.getBlocks(userId, [otherId]);
    if (blocks.blockedByMe.size > 0 || blocks.blockedMe.size > 0) return;
    const free = view.accepted || (view.requestSenderId === null && (await this.interactions.getMutualFollowers(userId, [otherId])).has(otherId));
    if (free) await this.events.typing(otherId, { conversationId, userId });
  }

  // ─── Chats de groupe (ADR-059) ───────────────────────────────────────────

  // Groupe privé avec au moins 2 amis (abonnés mutuels, sans blocage ni suspension), 32 membres au plus. Créateur
  // administrateur ; ligne « a créé le groupe » annoncée à tous, sans push.
  async createGroup(userId: string, input: CreateGroupInput): Promise<ConversationWithParticipant> {
    const ids = [...new Set(input.userIds)].filter((id) => id !== userId);
    if (ids.length < MIN_GROUP_FRIENDS) throw new InvalidGroupError(`Choisis au moins ${MIN_GROUP_FRIENDS} amis pour créer un groupe.`);
    if (ids.length + 1 > MAX_GROUP_MEMBERS) throw new InvalidGroupError(`Un groupe compte ${MAX_GROUP_MEMBERS} membres au plus.`);
    const name = this.groupName(input.name);
    await this.assertFriends(userId, ids);
    await this.limit(`group:${userId}`, GROUP_CREATE_RATE_LIMITS);
    const conversationId = await this.conversations.createGroup(userId, ids, name);
    const [created] = await this.conversations.listMessages(conversationId, null, null, 1);
    if (created) await this.announce(conversationId, [created]);
    return this.getConversation(userId, conversationId);
  }

  // Tout membre ajoute ses amis ; ils voient les messages à partir de leur ajout. Un compte déjà membre est ignoré.
  async addGroupMembers(userId: string, conversationId: string, userIds: string[]): Promise<ConversationWithParticipant> {
    const group = await this.group(conversationId, userId);
    const ids = [...new Set(userIds)].filter((id) => !group.members.some((m) => m.userId === id));
    if (ids.length > 0) {
      if (group.members.length + ids.length > MAX_GROUP_MEMBERS) throw new GroupFullError(MAX_GROUP_MEMBERS);
      await this.assertFriends(userId, ids);
      await this.limit(`message:${userId}`, MESSAGE_RATE_LIMITS);
      const events = await this.conversations.addMembers(conversationId, userId, ids, MAX_GROUP_MEMBERS);
      if (!events) throw new GroupFullError(MAX_GROUP_MEMBERS);
      await this.announce(conversationId, events);
    }
    return this.getConversation(userId, conversationId);
  }

  // L'administrateur seul retire un membre (pas lui-même : il quitte le groupe). Le membre retiré perd la conversation.
  async removeGroupMember(userId: string, conversationId: string, memberId: string): Promise<void> {
    const group = await this.group(conversationId, userId);
    if (memberId === userId) throw new InvalidGroupError('Pour sortir du groupe, quitte-le.');
    if (groupAdminId(group.members) !== userId) throw new NotGroupAdminError();
    if (!group.members.some((m) => m.userId === memberId)) throw new GroupMemberNotFoundError(memberId);
    const event = await this.conversations.removeMember(conversationId, userId, memberId);
    await this.announce(conversationId, [event]);
    await this.events.conversationDeleted(memberId, conversationId, await this.badges(memberId));
  }

  // Ses messages restent ; le membre arrivé juste après devient administrateur s'il l'était. Dernier membre : groupe supprimé.
  async leaveGroup(userId: string, conversationId: string): Promise<void> {
    await this.group(conversationId, userId);
    const event = await this.conversations.removeMember(conversationId, userId, userId);
    if (await this.conversations.findConversation(conversationId)) await this.announce(conversationId, [event]);
    await this.events.conversationDeleted(userId, conversationId, await this.badges(userId));
  }

  // Tout membre renomme le groupe ; un nom vide le retire (les noms des membres s'affichent).
  async renameGroup(userId: string, conversationId: string, name: string | null): Promise<ConversationWithParticipant> {
    const group = await this.group(conversationId, userId);
    const cleaned = this.groupName(name);
    if (cleaned !== group.name) {
      await this.limit(`message:${userId}`, MESSAGE_RATE_LIMITS);
      await this.announce(conversationId, [await this.conversations.rename(conversationId, userId, cleaned)]);
    }
    return this.getConversation(userId, conversationId);
  }

  // Sourdine : plus de notification push de ce groupe pour ce membre ; badge et temps réel inchangés.
  async setGroupMuted(userId: string, conversationId: string, muted: boolean): Promise<void> {
    await this.group(conversationId, userId);
    await this.conversations.setMuted(conversationId, userId, muted);
  }

  private async group(conversationId: string, userId: string): Promise<Conversation> {
    const conversation = await this.conversations.findConversation(conversationId);
    if (!conversation?.members.some((m) => m.userId === userId)) throw new ConversationNotFoundError(conversationId);
    if (conversation.kind !== 'group') throw new NotAGroupError();
    return conversation;
  }

  private groupName(name: string | null | undefined): string | null {
    const cleaned = name?.trim() ?? '';
    if (cleaned.length > MAX_GROUP_NAME_LENGTH) throw new InvalidGroupError(`Le nom du groupe compte ${MAX_GROUP_NAME_LENGTH} caractères au plus.`);
    return cleaned || null;
  }

  // Amis de `userId` (abonnés mutuels), sans blocage dans un sens ou l'autre, ni compte suspendu (ni inconnu).
  private async assertFriends(userId: string, ids: string[]): Promise<void> {
    const [mutual, blocks] = await Promise.all([this.interactions.getMutualFollowers(userId, ids), this.interactions.getBlocks(userId, ids)]);
    if (ids.some((id) => !mutual.has(id) || blocks.blockedByMe.has(id) || blocks.blockedMe.has(id))) throw new NotAFriendError();
  }

  // Lignes d'événement annoncées aux membres actuels (`messageCreated`), sauf à ceux qui ont un blocage avec leur auteur.
  private async announce(conversationId: string, events: Message[]): Promise<void> {
    for (const event of events) {
      const [item] = await this.withVideos(event.senderId, [event], true);
      await this.deliverToGroup(conversationId, event, item, false);
    }
  }

  // Message (ou ligne d'événement) remis aux membres du groupe : à chacun tel qu'il le voit, sauf à ceux qui ont un blocage
  // avec l'expéditeur (ADR-059) ; notification push (`push`) aux autres membres qui n'ont pas mis le groupe en sourdine.
  private async deliverToGroup(conversationId: string, message: Message, senderItem: MessageItem, push: boolean): Promise<void> {
    const conversation = await this.conversations.findConversation(conversationId);
    if (!conversation) return;
    const others = conversation.members.filter((m) => m.userId !== message.senderId);
    const recipients = await this.deliverable(
      message.senderId,
      others.map((m) => m.userId),
    );
    if (conversation.members.some((m) => m.userId === message.senderId)) {
      await this.events.messageCreated(message.senderId, senderItem, await this.badges(message.senderId));
    }
    const sender = push ? await this.users.getById(message.senderId) : null;
    const users = push
      ? new Map((await this.users.getByIds(conversation.members.map((m) => m.userId))).map((u) => [u.id, u]))
      : new Map<string, User>();
    for (const recipientId of recipients) {
      const [item] = await this.withVideos(recipientId, [message], true);
      await this.events.messageCreated(recipientId, item, await this.badges(recipientId));
      const muted = others.find((m) => m.userId === recipientId)?.mutedAt !== null;
      if (sender && !muted) {
        const title =
          conversation.name ??
          this.sortedMembers(conversation.members)
            .filter((m) => m.userId !== recipientId)
            .flatMap((m) => users.get(m.userId)?.displayName ?? [])
            .join(', ');
        await this.events.pushGroupMessage(recipientId, sender, title, item);
      }
    }
  }

  // Parmi `recipientIds`, ceux qui n'ont aucun blocage avec `senderId` (dans un sens ou l'autre) et ne sont pas suspendus.
  private async deliverable(senderId: string, recipientIds: string[]): Promise<string[]> {
    if (recipientIds.length === 0) return [];
    const blocks = await this.interactions.getBlocks(senderId, recipientIds);
    return recipientIds.filter((id) => !blocks.blockedByMe.has(id) && !blocks.blockedMe.has(id));
  }

  private async otherMembers(conversationId: string, userId: string): Promise<string[]> {
    const conversation = await this.conversations.findConversation(conversationId);
    return (conversation?.members ?? []).filter((m) => m.userId !== userId).map((m) => m.userId);
  }

  private sortedMembers(members: ConversationMember[]): ConversationMember[] {
    return [...members].sort((a, b) => a.joinedAt.getTime() - b.joinedAt.getTime() || (a.userId < b.userId ? -1 : 1));
  }

  // Comptes masqués au lecteur (blocages dans les deux sens, suspensions) : leurs messages sont cachés dans un groupe.
  private async hiddenIds(userId: string): Promise<string[]> {
    return [...(await this.interactions.getHiddenAccountIds(userId))];
  }

  async badges(userId: string): Promise<MessagingBadges> {
    const senders = await this.conversations.listPendingRequestSenders(userId);
    const blocks = await this.interactions.getBlocks(userId, senders);
    return {
      unreadConversations: await this.conversations.countUnreadConversations(userId, await this.hiddenIds(userId)),
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
    const ids = views.flatMap((v) => (v.participantId ? [v.participantId] : []));
    const groupIds = views.filter((v) => v.kind === 'group').map((v) => v.id);
    const members = await this.conversations.findMembers(groupIds);
    const memberIds = [...members.values()].flatMap((list) => list.map((m) => m.userId));
    const users = new Map((await this.users.getByIds([...new Set([...ids, ...memberIds])])).map((u) => [u.id, u]));
    const mutual = await this.interactions.getMutualFollowers(userId, ids);
    const blocks = await this.interactions.getBlocks(userId, ids);
    const last = (kind: string) => views.flatMap((v) => (v.lastMessage && v.kind === kind ? [v.lastMessage] : []));
    const lastMessages = new Map(
      [...(await this.withVideos(userId, last('direct'))), ...(await this.withVideos(userId, last('group'), true))].map((item) => [
        item.message.conversationId,
        item,
      ]),
    );
    return views.flatMap((conversation): ConversationWithParticipant[] => {
      if (conversation.kind === 'group') {
        const list = this.sortedMembers(members.get(conversation.id) ?? []);
        const group: GroupInfo = {
          name: conversation.name,
          adminId: groupAdminId(list) ?? userId,
          muted: list.some((m) => m.userId === userId && m.mutedAt !== null),
          members: list.flatMap((m) => {
            const user = users.get(m.userId);
            return user ? [{ user, joinedAt: m.joinedAt, lastReadMessageId: m.lastReadMessageId }] : [];
          }),
        };
        return [
          {
            conversation,
            lastMessage: lastMessages.get(conversation.id) ?? null,
            participant: null,
            group,
            status: 'direct' as const,
            canSend: true,
            remainingRequestMessages: null,
            blockedByMe: false,
            participantLastReadMessageId: null,
          },
        ];
      }
      const participant = users.get(conversation.participantId ?? '');
      if (!participant) return [];
      const status = this.status(conversation, mutual.has(participant.id));
      const blocked = blocks.blockedByMe.has(participant.id) || blocks.blockedMe.has(participant.id);
      const remaining = status === 'requestSent' ? Math.max(0, REQUEST_MESSAGE_LIMIT - conversation.ownMessageCount) : null;
      return [
        {
          conversation,
          lastMessage: lastMessages.get(conversation.id) ?? null,
          participant,
          group: null,
          status,
          canSend: !blocked && remaining !== 0,
          remainingRequestMessages: remaining,
          blockedByMe: blocks.blockedByMe.has(participant.id),
          participantLastReadMessageId: conversation.accepted ? conversation.participantLastReadMessageId : null,
        },
      ];
    });
  }

  // Vidéos partagées et stories auxquelles répondent les messages, telles que `viewerId` les voit : celles d'un compte
  // bloqué dans un sens ou dans l'autre, ou suspendu, sont indisponibles, comme dans le feed (blocages lus seulement s'il y
  // en a) ; une story expirée aussi.
  // Dans un groupe (`inGroup`), chaque message porte aussi son expéditeur et le membre visé par une ligne d'événement.
  private async withVideos(viewerId: string, messages: Message[], inGroup = false): Promise<MessageItem[]> {
    const liveIds = messages.flatMap((m) => (m.liveId ? [m.liveId] : []));
    const lives = liveIds.length > 0 ? await this.lives.getLivePreviews(liveIds, viewerId) : new Map<string, LiveItem>();
    const storyIds = messages.flatMap((m) => (m.storyId ? [m.storyId] : []));
    const stories = storyIds.length > 0 ? await this.stories.getStoryPreviews(storyIds, viewerId) : new Map<string, ActiveStory>();
    const videoIds = [...new Set(messages.flatMap((m) => (m.sharedVideoId ? [m.sharedVideoId] : [])))];
    const [published, hidden] = videoIds.length
      ? await Promise.all([this.videos.getPublishedVideos(videoIds, viewerId), this.interactions.getHiddenAccountIds(viewerId)])
      : [[], new Set<string>()];
    const videos = new Map(published.filter((v) => !hidden.has(v.userId)).map((v) => [v.id, v]));
    const people = inGroup ? messages.flatMap((m) => [m.senderId, ...(m.eventUserId ? [m.eventUserId] : [])]) : [];
    const users = new Map((await this.users.getByIds([...new Set([...[...videos.values()].map((v) => v.userId), ...people])])).map((u) => [u.id, u]));
    return messages.map((message) => {
      const repliedStory = message.storyId ? { id: message.storyId, story: stories.get(message.storyId) ?? null } : null;
      const sharedLive = message.liveId ? { id: message.liveId, item: lives.get(message.liveId) ?? null } : null;
      const people: Pick<MessageItem, 'sender' | 'eventUser'> = inGroup
        ? { sender: users.get(message.senderId) ?? null, ...(message.eventUserId ? { eventUser: users.get(message.eventUserId) ?? null } : {}) }
        : {};
      if (!message.sharedVideoId) return { message, sharedVideo: null, repliedStory, sharedLive, ...people };
      const video = videos.get(message.sharedVideoId) ?? null;
      const author = video ? (users.get(video.userId) ?? null) : null;
      // Vidéo supprimée, son auteur, ou compte bloqué : « indisponible ».
      return { message, sharedVideo: { id: message.sharedVideoId, video: author ? video : null, author }, repliedStory, sharedLive, ...people };
    });
  }
}
