import { randomUUID } from 'node:crypto';
import { ConversationRepository } from '../domain/conversation.repository';
import type { Conversation, ConversationKind, ConversationMember, ConversationView, GroupEvent, Message } from '../domain/messaging';

interface StoredConversation {
  createdAt: Date;
  kind: ConversationKind;
  name: string | null;
  requestSenderId: string | null;
  acceptedAt: Date | null;
  declinedAt: Date | null;
  members: Map<string, ConversationMember>;
}

const after = (id: string, marker: string | null) => !marker || id > marker;

// Adaptateur en mémoire pour les tests : mêmes règles que la base (une conversation par paire, repères
// de lecture et de suppression, demandes, groupes, identifiants croissants comme les UUID v7).
export class InMemoryConversationRepository extends ConversationRepository {
  readonly conversations = new Map<string, StoredConversation>();
  readonly messages: Message[] = [];
  // Identifiant d'envoi de chaque message (ADR-044), comme la colonne `client_message_id`.
  private readonly clientMessageIds = new Map<string, string>();
  private sequence = 0;
  // Horloge des entrées : strictement croissante, comme l'ordre d'arrivée dans un groupe.
  private clock = Date.now();

  async findOrCreateDirect(userId: string, otherUserId: string): Promise<string> {
    for (const [id, { kind, members }] of this.conversations) {
      if (kind === 'direct' && members.size === 2 && members.has(userId) && members.has(otherUserId)) return id;
    }
    const id = this.nextId();
    const members = new Map([userId, otherUserId].map((u) => [u, this.member(u, null)]));
    this.conversations.set(id, {
      createdAt: new Date(),
      kind: 'direct',
      name: null,
      requestSenderId: null,
      acceptedAt: null,
      declinedAt: null,
      members,
    });
    return id;
  }

  async findConversation(conversationId: string): Promise<Conversation | null> {
    const stored = this.conversations.get(conversationId);
    if (!stored) return null;
    const { members, ...rest } = stored;
    return { id: conversationId, ...rest, members: [...members.values()].map((m) => ({ ...m })) };
  }

  async findMembers(conversationIds: string[]): Promise<Map<string, ConversationMember[]>> {
    return new Map(conversationIds.map((id) => [id, [...(this.conversations.get(id)?.members.values() ?? [])].map((m) => ({ ...m }))]));
  }

  async createGroup(creatorId: string, memberIds: string[], name: string | null): Promise<string> {
    const id = this.nextId();
    const members = new Map([creatorId, ...memberIds].map((u) => [u, this.member(u, null)]));
    this.conversations.set(id, {
      createdAt: new Date(),
      kind: 'group',
      name,
      requestSenderId: null,
      acceptedAt: new Date(),
      declinedAt: null,
      members,
    });
    this.event(id, creatorId, 'created', null, '');
    return id;
  }

  async addMembers(conversationId: string, adderId: string, userIds: string[], maxMembers: number): Promise<Message[] | null> {
    const conversation = this.conversations.get(conversationId)!;
    const added = userIds.filter((id) => !conversation.members.has(id));
    if (conversation.members.size + added.length > maxMembers) return null;
    const last = this.lastMessageId(conversationId, null);
    for (const userId of added) conversation.members.set(userId, this.member(userId, last));
    return added.map((userId) => this.event(conversationId, adderId, 'added', userId, ''));
  }

  async removeMember(conversationId: string, actorId: string, memberId: string): Promise<Message> {
    const left = actorId === memberId;
    const event = this.event(conversationId, actorId, left ? 'left' : 'removed', left ? null : memberId, '');
    const conversation = this.conversations.get(conversationId)!;
    conversation.members.delete(memberId);
    // Trigger conversation_cleanup : un groupe sans membre est supprimé, avec ses messages.
    if (conversation.members.size === 0) this.deleteConversation(conversationId);
    return event;
  }

  async rename(conversationId: string, userId: string, name: string | null): Promise<Message> {
    this.conversations.get(conversationId)!.name = name;
    return this.event(conversationId, userId, 'renamed', null, name ?? '');
  }

  async setMuted(conversationId: string, userId: string, muted: boolean): Promise<void> {
    const member = this.conversations.get(conversationId)?.members.get(userId);
    if (member && muted !== (member.mutedAt !== null)) member.mutedAt = muted ? new Date() : null;
  }

  // Simule la suppression d'un compte : cascade de la base (participations, messages envoyés), puis
  // trigger conversation_cleanup (une conversation à deux restée à moins de deux participants, ou un groupe vide, est supprimé).
  removeUser(userId: string): void {
    for (const [id, { kind, members }] of this.conversations) {
      if (members.delete(userId) && members.size < (kind === 'group' ? 1 : 2)) this.conversations.delete(id);
    }
    const remaining = this.messages.filter((m) => m.senderId !== userId && this.conversations.has(m.conversationId));
    this.messages.splice(0, this.messages.length, ...remaining);
  }

  async findView(conversationId: string, userId: string, hiddenSenderIds: string[] = []): Promise<ConversationView | null> {
    return this.view(conversationId, userId, hiddenSenderIds);
  }

  async listInbox(userId: string, beforeMessageId: string | null, limit: number, hiddenSenderIds: string[] = []): Promise<ConversationView[]> {
    return this.list(userId, beforeMessageId, limit, hiddenSenderIds, (v) => v.accepted || v.requestSenderId === userId);
  }

  async listRequests(userId: string, beforeMessageId: string | null, limit: number): Promise<ConversationView[]> {
    return this.list(userId, beforeMessageId, limit, [], (v) => !v.accepted && !v.declined && v.requestSenderId === v.participantId);
  }

  async listPendingRequestSenders(userId: string): Promise<string[]> {
    return (await this.listRequests(userId, null, Number.MAX_SAFE_INTEGER)).map((v) => v.participantId!);
  }

  async addMessage(input: {
    conversationId: string;
    senderId: string;
    content: string;
    sharedVideoId: string | null;
    storyId: string | null;
    liveId: string | null;
    clientMessageId: string | null;
    accept: boolean;
    openRequest: boolean;
  }): Promise<Message | null> {
    if (input.clientMessageId && (await this.findByClientMessageId(input.senderId, input.clientMessageId))) return null;
    const created: Message = {
      id: this.nextId(),
      conversationId: input.conversationId,
      senderId: input.senderId,
      content: input.content,
      sharedVideoId: input.sharedVideoId,
      storyId: input.storyId,
      liveId: input.liveId,
      event: null,
      eventUserId: null,
      createdAt: new Date(),
    };
    this.messages.push(created);
    if (input.clientMessageId) this.clientMessageIds.set(created.id, input.clientMessageId);
    const conversation = this.conversations.get(input.conversationId)!;
    conversation.members.get(input.senderId)!.lastReadMessageId = created.id;
    if (input.accept) Object.assign(conversation, { acceptedAt: new Date(), declinedAt: null });
    if (input.openRequest) conversation.requestSenderId = input.senderId;
    return created;
  }

  async findByClientMessageId(senderId: string, clientMessageId: string): Promise<Message | null> {
    return this.messages.find((m) => m.senderId === senderId && this.clientMessageIds.get(m.id) === clientMessageId) ?? null;
  }

  async findMessage(messageId: string): Promise<Message | null> {
    return this.messages.find((m) => m.id === messageId) ?? null;
  }

  async findMessagesByIds(ids: string[]): Promise<Message[]> {
    return this.messages.filter((m) => ids.includes(m.id));
  }

  async deleteMessage(messageId: string): Promise<void> {
    const index = this.messages.findIndex((m) => m.id === messageId);
    if (index >= 0) this.messages.splice(index, 1);
  }

  async searchMessages(userId: string, query: string, limit: number, hiddenSenderIds: string[] = []): Promise<Message[]> {
    const needle = query.toLowerCase();
    return this.messages
      .filter((m) => {
        const conversation = this.conversations.get(m.conversationId);
        const member = conversation?.members.get(userId);
        if (!conversation || !member || !after(m.id, member.clearedUpToMessageId) || m.event) return false;
        if (conversation.kind === 'group' && hiddenSenderIds.includes(m.senderId)) return false;
        if (conversation.declinedAt && conversation.requestSenderId !== userId) return false;
        return m.content.toLowerCase().includes(needle);
      })
      .sort((a, b) => (a.id < b.id ? 1 : -1))
      .slice(0, limit);
  }

  async listMessages(conversationId: string, beforeId: string | null, afterId: string | null, limit: number): Promise<Message[]> {
    return this.messages
      .filter((m) => m.conversationId === conversationId && (!beforeId || m.id < beforeId) && after(m.id, afterId))
      .sort((a, b) => (a.id < b.id ? 1 : -1))
      .slice(0, limit);
  }

  async markRead(conversationId: string, userId: string, upToId: string | null): Promise<string | null> {
    const member = this.conversations.get(conversationId)?.members.get(userId);
    const target = this.lastMessageId(conversationId, upToId);
    if (!member || !target || (member.lastReadMessageId && member.lastReadMessageId >= target)) return null;
    member.lastReadMessageId = target;
    return target;
  }

  async clearFor(conversationId: string, userId: string): Promise<void> {
    const member = this.conversations.get(conversationId)?.members.get(userId);
    const last = this.lastMessageId(conversationId, null);
    if (!member || !last) return;
    member.clearedUpToMessageId = last;
    if (!member.lastReadMessageId || member.lastReadMessageId < last) member.lastReadMessageId = last;
  }

  async accept(conversationId: string): Promise<void> {
    Object.assign(this.conversations.get(conversationId)!, { acceptedAt: new Date(), declinedAt: null });
  }

  async decline(conversationId: string): Promise<void> {
    this.conversations.get(conversationId)!.declinedAt = new Date();
  }

  async countUnreadConversations(userId: string, hiddenSenderIds: string[] = []): Promise<number> {
    return [...this.conversations.keys()].filter((id) => {
      const view = this.view(id, userId, hiddenSenderIds);
      return view?.accepted && view.unreadCount > 0;
    }).length;
  }

  private list(
    userId: string,
    before: string | null,
    limit: number,
    hidden: string[],
    keep: (view: ConversationView) => boolean,
  ): ConversationView[] {
    return [...this.conversations.keys()]
      .flatMap((id) => {
        const view = this.view(id, userId, hidden);
        return view?.lastMessage && (!before || view.lastMessage.id < before) && keep(view) ? [view] : [];
      })
      .sort((a, b) => (a.lastMessage!.id < b.lastMessage!.id ? 1 : -1))
      .slice(0, limit);
  }

  private lastMessageId(conversationId: string, upToId: string | null): string | null {
    return this.messages
      .filter((m) => m.conversationId === conversationId && (!upToId || m.id <= upToId))
      .reduce<string | null>((max, m) => (!max || m.id > max ? m.id : max), null);
  }

  private view(conversationId: string, userId: string, hidden: string[]): ConversationView | null {
    const conversation = this.conversations.get(conversationId);
    const me = conversation?.members.get(userId);
    const group = conversation?.kind === 'group';
    const other = conversation && !group ? [...conversation.members.values()].find((m) => m.userId !== userId) : undefined;
    if (!conversation || !me || (!group && !other)) return null;
    const all = this.messages.filter((m) => m.conversationId === conversationId).sort((a, b) => (a.id < b.id ? -1 : 1));
    const visible = all.filter((m) => after(m.id, me.clearedUpToMessageId) && !(group && hidden.includes(m.senderId)));
    return {
      id: conversationId,
      createdAt: conversation.createdAt,
      kind: conversation.kind,
      name: conversation.name,
      requestSenderId: conversation.requestSenderId,
      accepted: conversation.acceptedAt !== null,
      declined: conversation.declinedAt !== null,
      participantId: other?.userId ?? null,
      lastMessage: visible.at(-1) ?? null,
      unreadCount: visible.filter((m) => m.senderId !== userId && !m.event && after(m.id, me.lastReadMessageId)).length,
      participantLastReadMessageId: other?.lastReadMessageId ?? null,
      ownMessageCount: conversation.acceptedAt ? 0 : all.filter((m) => m.senderId === userId).length,
    };
  }

  // Ligne d'événement d'un groupe, lue par son auteur.
  private event(conversationId: string, senderId: string, event: GroupEvent, eventUserId: string | null, content: string): Message {
    const created: Message = {
      id: this.nextId(),
      conversationId,
      senderId,
      content,
      sharedVideoId: null,
      storyId: null,
      liveId: null,
      event,
      eventUserId,
      createdAt: new Date(),
    };
    this.messages.push(created);
    const member = this.conversations.get(conversationId)?.members.get(senderId);
    if (member) member.lastReadMessageId = created.id;
    return created;
  }

  private member(userId: string, lastMessageId: string | null): ConversationMember {
    return { userId, lastReadMessageId: lastMessageId, clearedUpToMessageId: lastMessageId, joinedAt: new Date(++this.clock), mutedAt: null };
  }

  private deleteConversation(conversationId: string): void {
    this.conversations.delete(conversationId);
    const remaining = this.messages.filter((m) => m.conversationId !== conversationId);
    this.messages.splice(0, this.messages.length, ...remaining);
  }

  private nextId(): string {
    return `${String(++this.sequence).padStart(8, '0')}-${randomUUID()}`;
  }
}
