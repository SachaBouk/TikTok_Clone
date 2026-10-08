import { randomUUID } from 'node:crypto';
import { ConversationRepository } from '../domain/conversation.repository';
import type { Conversation, ConversationMember, ConversationView, Message } from '../domain/messaging';

interface StoredConversation {
  createdAt: Date;
  requestSenderId: string | null;
  acceptedAt: Date | null;
  declinedAt: Date | null;
  members: Map<string, ConversationMember>;
}

const after = (id: string, marker: string | null) => !marker || id > marker;

// Adaptateur en mémoire pour les tests : mêmes règles que la base (une conversation par paire, repères
// de lecture et de suppression, demandes, identifiants croissants comme les UUID v7).
export class InMemoryConversationRepository extends ConversationRepository {
  readonly conversations = new Map<string, StoredConversation>();
  readonly messages: Message[] = [];
  // Identifiant d'envoi de chaque message (ADR-044), comme la colonne `client_message_id`.
  private readonly clientMessageIds = new Map<string, string>();
  private sequence = 0;

  async findOrCreateDirect(userId: string, otherUserId: string): Promise<string> {
    for (const [id, { members }] of this.conversations) {
      if (members.size === 2 && members.has(userId) && members.has(otherUserId)) return id;
    }
    const id = this.nextId();
    const members = new Map([userId, otherUserId].map((u) => [u, { userId: u, lastReadMessageId: null, clearedUpToMessageId: null }]));
    this.conversations.set(id, { createdAt: new Date(), requestSenderId: null, acceptedAt: null, declinedAt: null, members });
    return id;
  }

  async findConversation(conversationId: string): Promise<Conversation | null> {
    const stored = this.conversations.get(conversationId);
    if (!stored) return null;
    const { members, ...rest } = stored;
    return { id: conversationId, ...rest, members: [...members.values()].map((m) => ({ ...m })) };
  }

  // Simule la suppression d'un compte : cascade de la base (participations, messages envoyés), puis
  // trigger conversation_cleanup (une conversation à moins de deux participants est supprimée).
  removeUser(userId: string): void {
    for (const [id, { members }] of this.conversations) {
      if (members.delete(userId) && members.size < 2) this.conversations.delete(id);
    }
    const remaining = this.messages.filter((m) => m.senderId !== userId && this.conversations.has(m.conversationId));
    this.messages.splice(0, this.messages.length, ...remaining);
  }

  async findView(conversationId: string, userId: string): Promise<ConversationView | null> {
    return this.view(conversationId, userId);
  }

  async listInbox(userId: string, beforeMessageId: string | null, limit: number): Promise<ConversationView[]> {
    return this.list(userId, beforeMessageId, limit, (v) => v.accepted || v.requestSenderId === userId);
  }

  async listRequests(userId: string, beforeMessageId: string | null, limit: number): Promise<ConversationView[]> {
    return this.list(userId, beforeMessageId, limit, (v) => !v.accepted && !v.declined && v.requestSenderId === v.participantId);
  }

  async listPendingRequestSenders(userId: string): Promise<string[]> {
    return (await this.listRequests(userId, null, Number.MAX_SAFE_INTEGER)).map((v) => v.participantId);
  }

  async addMessage(input: {
    conversationId: string;
    senderId: string;
    content: string;
    sharedVideoId: string | null;
    storyId: string | null;
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

  async countUnreadConversations(userId: string): Promise<number> {
    return [...this.conversations.keys()].filter((id) => {
      const view = this.view(id, userId);
      return view?.accepted && view.unreadCount > 0;
    }).length;
  }

  private list(userId: string, before: string | null, limit: number, keep: (view: ConversationView) => boolean): ConversationView[] {
    return [...this.conversations.keys()]
      .flatMap((id) => {
        const view = this.view(id, userId);
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

  private view(conversationId: string, userId: string): ConversationView | null {
    const conversation = this.conversations.get(conversationId);
    const me = conversation?.members.get(userId);
    const other = conversation && [...conversation.members.values()].find((m) => m.userId !== userId);
    if (!conversation || !me || !other) return null;
    const all = this.messages.filter((m) => m.conversationId === conversationId).sort((a, b) => (a.id < b.id ? -1 : 1));
    const visible = all.filter((m) => after(m.id, me.clearedUpToMessageId));
    return {
      id: conversationId,
      createdAt: conversation.createdAt,
      requestSenderId: conversation.requestSenderId,
      accepted: conversation.acceptedAt !== null,
      declined: conversation.declinedAt !== null,
      participantId: other.userId,
      lastMessage: visible.at(-1) ?? null,
      unreadCount: visible.filter((m) => m.senderId !== userId && after(m.id, me.lastReadMessageId)).length,
      participantLastReadMessageId: other.lastReadMessageId,
      ownMessageCount: conversation.acceptedAt ? 0 : all.filter((m) => m.senderId === userId).length,
    };
  }

  private nextId(): string {
    return `${String(++this.sequence).padStart(8, '0')}-${randomUUID()}`;
  }
}
