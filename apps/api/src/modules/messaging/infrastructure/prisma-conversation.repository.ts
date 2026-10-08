import { Injectable } from '@nestjs/common';
import { Prisma } from '../../../generated/prisma/client';
import { violatedUniqueConstraint } from '../../../database/prisma-errors';
import { PrismaService } from '../../../database/prisma.service';
import { ConversationRepository } from '../domain/conversation.repository';
import type { Conversation, ConversationView, Message } from '../domain/messaging';

const messageSelect = {
  id: true,
  conversationId: true,
  senderId: true,
  content: true,
  sharedVideoId: true,
  storyId: true,
  createdAt: true,
} as const;
// Plus petit UUID : repère « rien de lu / rien de supprimé ».
const ZERO = Prisma.sql`'00000000-0000-0000-0000-000000000000'::uuid`;
// Demande reçue en attente : ni acceptée ni refusée, ouverte par l'autre participant.
const REQUEST_RECEIVED = Prisma.sql`c.accepted_at IS NULL AND c.declined_at IS NULL AND c.request_sender_id = other.user_id`;

interface ViewRow {
  id: string;
  created_at: Date;
  request_sender_id: string | null;
  accepted_at: Date | null;
  declined_at: Date | null;
  participant_id: string;
  participant_last_read: string | null;
  last_id: string | null;
  last_sender_id: string | null;
  last_content: string | null;
  last_shared_video_id: string | null;
  last_story_id: string | null;
  last_created_at: Date | null;
  unread_count: number;
  own_count: number;
}

// Tables conversations, conversation_participants, messages. Vues de conversation (dernier message visible,
// non-lus, repère de l'autre, messages envoyés d'une demande) en SQL : une requête par page.
@Injectable()
export class PrismaConversationRepository extends ConversationRepository {
  constructor(private readonly prisma: PrismaService) {
    super();
  }

  // Verrou transactionnel sur la paire : deux ouvertures simultanées ne créent pas deux conversations.
  // (Le modèle ADR-006, à participants, ne permet pas de contrainte d'unicité sur la paire.)
  findOrCreateDirect(userId: string, otherUserId: string): Promise<string> {
    const [a, b] = [userId, otherUserId].sort();
    return this.prisma.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${`conversation:${a}:${b}`}, 0))`;
      const [existing] = await tx.$queryRaw<{ conversation_id: string }[]>`
        SELECT p.conversation_id FROM conversation_participants p
        JOIN conversation_participants q ON q.conversation_id = p.conversation_id AND q.user_id = ${b}::uuid
        WHERE p.user_id = ${a}::uuid
          AND (SELECT count(*) FROM conversation_participants r WHERE r.conversation_id = p.conversation_id) = 2
        LIMIT 1`;
      if (existing) return existing.conversation_id;
      const created = await tx.conversation.create({
        data: { participants: { create: [{ userId: a }, { userId: b }] } },
        select: { id: true },
      });
      return created.id;
    });
  }

  async findConversation(conversationId: string): Promise<Conversation | null> {
    const row = await this.prisma.conversation.findUnique({
      where: { id: conversationId },
      select: {
        id: true,
        createdAt: true,
        requestSenderId: true,
        acceptedAt: true,
        declinedAt: true,
        participants: { select: { userId: true, lastReadMessageId: true, clearedUpToMessageId: true } },
      },
    });
    if (!row) return null;
    const { participants, ...conversation } = row;
    return { ...conversation, members: participants };
  }

  async findView(conversationId: string, userId: string): Promise<ConversationView | null> {
    const [view] = await this.views(userId, Prisma.sql`c.conversation_id = ${conversationId}::uuid`, { listed: false, before: null }, 1);
    return view ?? null;
  }

  listInbox(userId: string, beforeMessageId: string | null, limit: number): Promise<ConversationView[]> {
    return this.views(
      userId,
      Prisma.sql`(c.accepted_at IS NOT NULL OR c.request_sender_id = me.user_id)`,
      { listed: true, before: beforeMessageId },
      limit,
    );
  }

  listRequests(userId: string, beforeMessageId: string | null, limit: number): Promise<ConversationView[]> {
    return this.views(userId, REQUEST_RECEIVED, { listed: true, before: beforeMessageId }, limit);
  }

  async listPendingRequestSenders(userId: string): Promise<string[]> {
    const rows = await this.prisma.$queryRaw<{ participant_id: string }[]>`
      SELECT other.user_id AS participant_id
      FROM conversation_participants me
      JOIN conversations c ON c.conversation_id = me.conversation_id
      JOIN conversation_participants other ON other.conversation_id = me.conversation_id AND other.user_id <> me.user_id
      WHERE me.user_id = ${userId}::uuid AND ${REQUEST_RECEIVED}
        AND EXISTS (SELECT 1 FROM messages m WHERE m.conversation_id = c.conversation_id
                    AND m.message_id > COALESCE(me.cleared_up_to_message_id, ${ZERO}))`;
    return rows.map((r) => r.participant_id);
  }

  // Le message, le repère de lecture de l'expéditeur et l'état de la conversation, ensemble.
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
    try {
      return await this.addMessageNow(input);
    } catch (error) {
      // Index unique `messages_client_message_key` : même identifiant d'envoi déjà enregistré (envois simultanés).
      if (violatedUniqueConstraint(error) === 'messages_client_message_key') return null;
      throw error;
    }
  }

  findByClientMessageId(senderId: string, clientMessageId: string): Promise<Message | null> {
    return this.prisma.message.findUnique({ where: { senderId_clientMessageId: { senderId, clientMessageId } }, select: messageSelect });
  }

  private addMessageNow(input: {
    conversationId: string;
    senderId: string;
    content: string;
    sharedVideoId: string | null;
    storyId: string | null;
    clientMessageId: string | null;
    accept: boolean;
    openRequest: boolean;
  }): Promise<Message> {
    return this.prisma.$transaction(async (tx) => {
      const created = await tx.message.create({
        data: {
          conversationId: input.conversationId,
          senderId: input.senderId,
          content: input.content,
          sharedVideoId: input.sharedVideoId,
          storyId: input.storyId,
          clientMessageId: input.clientMessageId,
        },
        select: messageSelect,
      });
      await tx.conversationParticipant.updateMany({
        where: { conversationId: input.conversationId, userId: input.senderId },
        data: { lastReadMessageId: created.id },
      });
      if (input.accept || input.openRequest) {
        await tx.conversation.update({
          where: { id: input.conversationId },
          data: {
            ...(input.accept ? { acceptedAt: new Date(), declinedAt: null } : {}),
            ...(input.openRequest ? { requestSenderId: input.senderId } : {}),
          },
        });
      }
      return created;
    });
  }

  findMessage(messageId: string): Promise<Message | null> {
    return this.prisma.message.findUnique({ where: { id: messageId }, select: messageSelect });
  }

  async findMessagesByIds(ids: string[]): Promise<Message[]> {
    if (ids.length === 0) return [];
    return this.prisma.message.findMany({ where: { id: { in: ids } }, select: messageSelect });
  }

  async deleteMessage(messageId: string): Promise<void> {
    await this.prisma.message.deleteMany({ where: { id: messageId } });
  }

  listMessages(conversationId: string, beforeId: string | null, afterId: string | null, limit: number): Promise<Message[]> {
    return this.prisma.message.findMany({
      where: {
        conversationId,
        ...(beforeId || afterId ? { id: { ...(beforeId ? { lt: beforeId } : {}), ...(afterId ? { gt: afterId } : {}) } } : {}),
      },
      orderBy: { id: 'desc' },
      take: limit,
      select: messageSelect,
    });
  }

  // Le repère est ramené au dernier message existant ≤ upToId : un identifiant arbitraire ne marque pas
  // comme lus des messages à venir.
  async markRead(conversationId: string, userId: string, upToId: string | null): Promise<string | null> {
    const target = await this.lastMessageId(conversationId, upToId);
    if (!target) return null;
    const { count } = await this.prisma.conversationParticipant.updateMany({
      where: { conversationId, userId, OR: [{ lastReadMessageId: null }, { lastReadMessageId: { lt: target } }] },
      data: { lastReadMessageId: target },
    });
    return count > 0 ? target : null;
  }

  // Suppression pour soi : repère de suppression au dernier message, et lecture jusque-là.
  async clearFor(conversationId: string, userId: string): Promise<void> {
    const last = await this.lastMessageId(conversationId, null);
    if (!last) return;
    await this.prisma.$executeRaw`
      UPDATE conversation_participants
      SET cleared_up_to_message_id = ${last}::uuid,
          last_read_message_id = GREATEST(COALESCE(last_read_message_id, ${ZERO}), ${last}::uuid)
      WHERE conversation_id = ${conversationId}::uuid AND user_id = ${userId}::uuid`;
  }

  async accept(conversationId: string): Promise<void> {
    await this.prisma.conversation.update({ where: { id: conversationId }, data: { acceptedAt: new Date(), declinedAt: null } });
  }

  async decline(conversationId: string): Promise<void> {
    await this.prisma.conversation.update({ where: { id: conversationId }, data: { declinedAt: new Date() } });
  }

  async countUnreadConversations(userId: string): Promise<number> {
    const [row] = await this.prisma.$queryRaw<{ count: number }[]>`
      SELECT count(*)::int AS count FROM conversation_participants me
      JOIN conversations c ON c.conversation_id = me.conversation_id
      WHERE me.user_id = ${userId}::uuid AND c.accepted_at IS NOT NULL AND EXISTS (
        SELECT 1 FROM messages m
        WHERE m.conversation_id = me.conversation_id AND m.sender_id <> me.user_id
          AND m.message_id > GREATEST(COALESCE(me.last_read_message_id, ${ZERO}), COALESCE(me.cleared_up_to_message_id, ${ZERO})))`;
    return row?.count ?? 0;
  }

  private async lastMessageId(conversationId: string, upToId: string | null): Promise<string | null> {
    const last = await this.prisma.message.findFirst({
      where: { conversationId, ...(upToId ? { id: { lte: upToId } } : {}) },
      orderBy: { id: 'desc' },
      select: { id: true },
    });
    return last?.id ?? null;
  }

  // Conversations de `userId` vues par lui (messages supprimés pour lui exclus). L'autre participant
  // manquant (compte supprimé) : pas de ligne. Listes (`listed`) : seulement celles ayant un message visible,
  // strictement avant `before` (identifiant du dernier message) s'il est donné.
  private async views(
    userId: string,
    filter: Prisma.Sql,
    { listed, before }: { listed: boolean; before: string | null },
    limit: number,
  ): Promise<ConversationView[]> {
    const list = !listed
      ? Prisma.empty
      : before
        ? Prisma.sql`AND last.message_id IS NOT NULL AND last.message_id < ${before}::uuid`
        : Prisma.sql`AND last.message_id IS NOT NULL`;
    const rows = await this.prisma.$queryRaw<ViewRow[]>`
      SELECT c.conversation_id AS id, c.created_at, c.request_sender_id, c.accepted_at, c.declined_at,
             other.user_id AS participant_id, other.last_read_message_id AS participant_last_read,
             last.message_id AS last_id, last.sender_id AS last_sender_id, last.content AS last_content,
             last.shared_video_id AS last_shared_video_id, last.story_id AS last_story_id, last.created_at AS last_created_at,
             (SELECT count(*)::int FROM messages u
               WHERE u.conversation_id = c.conversation_id AND u.sender_id <> me.user_id
                 AND u.message_id > GREATEST(COALESCE(me.last_read_message_id, ${ZERO}), COALESCE(me.cleared_up_to_message_id, ${ZERO}))
             ) AS unread_count,
             CASE WHEN c.accepted_at IS NULL
               THEN (SELECT count(*)::int FROM messages o WHERE o.conversation_id = c.conversation_id AND o.sender_id = me.user_id)
               ELSE 0 END AS own_count
      FROM conversation_participants me
      JOIN conversations c ON c.conversation_id = me.conversation_id
      JOIN conversation_participants other ON other.conversation_id = me.conversation_id AND other.user_id <> me.user_id
      LEFT JOIN LATERAL (
        SELECT m.message_id, m.sender_id, m.content, m.shared_video_id, m.story_id, m.created_at FROM messages m
        WHERE m.conversation_id = c.conversation_id AND m.message_id > COALESCE(me.cleared_up_to_message_id, ${ZERO})
        ORDER BY m.message_id DESC LIMIT 1
      ) last ON true
      WHERE me.user_id = ${userId}::uuid AND ${filter} ${list}
      ORDER BY last.message_id DESC NULLS LAST
      LIMIT ${limit}`;
    return rows.map((row) => ({
      id: row.id,
      createdAt: row.created_at,
      requestSenderId: row.request_sender_id,
      accepted: row.accepted_at !== null,
      declined: row.declined_at !== null,
      participantId: row.participant_id,
      lastMessage: row.last_id
        ? {
            id: row.last_id,
            conversationId: row.id,
            senderId: row.last_sender_id!,
            content: row.last_content!,
            sharedVideoId: row.last_shared_video_id,
            storyId: row.last_story_id,
            createdAt: row.last_created_at!,
          }
        : null,
      unreadCount: row.unread_count,
      participantLastReadMessageId: row.participant_last_read,
      ownMessageCount: row.own_count,
    }));
  }
}
