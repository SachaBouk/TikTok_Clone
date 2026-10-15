import { Injectable } from '@nestjs/common';
import { Prisma } from '../../../generated/prisma/client';
import { violatedUniqueConstraint } from '../../../database/prisma-errors';
import { PrismaService } from '../../../database/prisma.service';
import { ConversationRepository } from '../domain/conversation.repository';
import type { Conversation, ConversationKind, ConversationMember, ConversationView, GroupEvent, Message } from '../domain/messaging';

const messageSelect = {
  id: true,
  conversationId: true,
  senderId: true,
  content: true,
  sharedVideoId: true,
  storyId: true,
  liveId: true,
  event: true,
  eventUserId: true,
  createdAt: true,
} as const;
const memberSelect = { userId: true, lastReadMessageId: true, clearedUpToMessageId: true, joinedAt: true, mutedAt: true } as const;
// Plus petit UUID : repère « rien de lu / rien de supprimé ».
const ZERO = Prisma.sql`'00000000-0000-0000-0000-000000000000'::uuid`;
// Message non lu par `me` : d'un autre, après ses repères de lecture et de suppression ; jamais une ligne d'événement ni,
// dans un groupe, un message d'un compte masqué au lecteur (ADR-059). `m` : alias de la table des messages.
function unread(hidden: string[], m: Prisma.Sql): Prisma.Sql {
  return Prisma.sql`${m}.sender_id <> me.user_id AND ${m}.event IS NULL
    AND (c.kind = 'direct' OR ${m}.sender_id <> ALL(${hidden}::uuid[]))
    AND ${m}.message_id > GREATEST(COALESCE(me.last_read_message_id, ${ZERO}), COALESCE(me.cleared_up_to_message_id, ${ZERO}))`;
}

// Demande reçue en attente : ni acceptée ni refusée, ouverte par l'autre participant.
const REQUEST_RECEIVED = Prisma.sql`c.accepted_at IS NULL AND c.declined_at IS NULL AND c.request_sender_id = other.user_id`;

interface ViewRow {
  id: string;
  created_at: Date;
  kind: ConversationKind;
  name: string | null;
  request_sender_id: string | null;
  accepted_at: Date | null;
  declined_at: Date | null;
  participant_id: string | null;
  participant_last_read: string | null;
  last_id: string | null;
  last_sender_id: string | null;
  last_content: string | null;
  last_shared_video_id: string | null;
  last_story_id: string | null;
  last_live_id: string | null;
  last_event: GroupEvent | null;
  last_event_user_id: string | null;
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
        JOIN conversations c ON c.conversation_id = p.conversation_id AND c.kind = 'direct'
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
        kind: true,
        name: true,
        requestSenderId: true,
        acceptedAt: true,
        declinedAt: true,
        participants: { select: memberSelect },
      },
    });
    if (!row) return null;
    const { participants, ...conversation } = row;
    return { ...conversation, members: participants };
  }

  async findMembers(conversationIds: string[]): Promise<Map<string, ConversationMember[]>> {
    const result = new Map<string, ConversationMember[]>(conversationIds.map((id) => [id, []]));
    if (conversationIds.length === 0) return result;
    const rows = await this.prisma.conversationParticipant.findMany({
      where: { conversationId: { in: conversationIds } },
      select: { conversationId: true, ...memberSelect },
    });
    for (const { conversationId, ...member } of rows) result.get(conversationId)?.push(member);
    return result;
  }

  // Créateur entré une milliseconde avant les autres : il est l'administrateur (le plus ancien membre).
  createGroup(creatorId: string, memberIds: string[], name: string | null): Promise<string> {
    const now = Date.now();
    return this.prisma.$transaction(async (tx) => {
      const { id } = await tx.conversation.create({
        data: {
          kind: 'group',
          name,
          acceptedAt: new Date(now),
          participants: {
            create: [{ userId: creatorId, joinedAt: new Date(now) }, ...memberIds.map((userId) => ({ userId, joinedAt: new Date(now + 1) }))],
          },
        },
        select: { id: true },
      });
      const created = await tx.message.create({
        data: { conversationId: id, senderId: creatorId, content: '', event: 'created' },
        select: { id: true },
      });
      await tx.conversationParticipant.update({
        where: { conversationId_userId: { conversationId: id, userId: creatorId } },
        data: { lastReadMessageId: created.id },
      });
      return id;
    });
  }

  // Verrou sur la ligne du groupe : deux ajouts simultanés ne dépassent pas la limite.
  addMembers(conversationId: string, adderId: string, userIds: string[], maxMembers: number): Promise<Message[] | null> {
    return this.prisma.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT 1 FROM conversations WHERE conversation_id = ${conversationId}::uuid FOR UPDATE`;
      const existing = await tx.conversationParticipant.findMany({ where: { conversationId }, select: { userId: true } });
      const added = userIds.filter((id) => !existing.some((m) => m.userId === id));
      if (existing.length + added.length > maxMembers) return null;
      const last = await tx.message.findFirst({ where: { conversationId }, orderBy: { id: 'desc' }, select: { id: true } });
      await tx.conversationParticipant.createMany({
        data: added.map((userId) => ({ conversationId, userId, lastReadMessageId: last?.id ?? null, clearedUpToMessageId: last?.id ?? null })),
      });
      const events: Message[] = [];
      for (const userId of added) {
        events.push(
          await tx.message.create({
            data: { conversationId, senderId: adderId, content: '', event: 'added', eventUserId: userId },
            select: messageSelect,
          }),
        );
      }
      if (events.length > 0) {
        await tx.conversationParticipant.updateMany({ where: { conversationId, userId: adderId }, data: { lastReadMessageId: events.at(-1)!.id } });
      }
      return events;
    });
  }

  // La ligne d'événement d'abord : le dernier départ supprime le groupe (trigger), et la ligne avec lui.
  removeMember(conversationId: string, actorId: string, memberId: string): Promise<Message> {
    return this.prisma.$transaction(async (tx) => {
      const left = actorId === memberId;
      const event = await tx.message.create({
        data: { conversationId, senderId: actorId, content: '', event: left ? 'left' : 'removed', eventUserId: left ? null : memberId },
        select: messageSelect,
      });
      if (!left) await tx.conversationParticipant.updateMany({ where: { conversationId, userId: actorId }, data: { lastReadMessageId: event.id } });
      await tx.conversationParticipant.deleteMany({ where: { conversationId, userId: memberId } });
      return event;
    });
  }

  rename(conversationId: string, userId: string, name: string | null): Promise<Message> {
    return this.prisma.$transaction(async (tx) => {
      await tx.conversation.update({ where: { id: conversationId }, data: { name } });
      const event = await tx.message.create({
        data: { conversationId, senderId: userId, content: name ?? '', event: 'renamed' },
        select: messageSelect,
      });
      await tx.conversationParticipant.updateMany({ where: { conversationId, userId }, data: { lastReadMessageId: event.id } });
      return event;
    });
  }

  async setMuted(conversationId: string, userId: string, muted: boolean): Promise<void> {
    await this.prisma.conversationParticipant.updateMany({
      where: { conversationId, userId, ...(muted ? { mutedAt: null } : {}) },
      data: { mutedAt: muted ? new Date() : null },
    });
  }

  async findView(conversationId: string, userId: string, hiddenSenderIds: string[] = []): Promise<ConversationView | null> {
    const [view] = await this.views(
      userId,
      Prisma.sql`c.conversation_id = ${conversationId}::uuid`,
      { listed: false, before: null, hidden: hiddenSenderIds },
      1,
    );
    return view ?? null;
  }

  listInbox(userId: string, beforeMessageId: string | null, limit: number, hiddenSenderIds: string[] = []): Promise<ConversationView[]> {
    return this.views(
      userId,
      Prisma.sql`(c.accepted_at IS NOT NULL OR c.request_sender_id = me.user_id)`,
      { listed: true, before: beforeMessageId, hidden: hiddenSenderIds },
      limit,
    );
  }

  listRequests(userId: string, beforeMessageId: string | null, limit: number): Promise<ConversationView[]> {
    return this.views(userId, REQUEST_RECEIVED, { listed: true, before: beforeMessageId, hidden: [] }, limit);
  }

  async listPendingRequestSenders(userId: string): Promise<string[]> {
    const rows = await this.prisma.$queryRaw<{ participant_id: string }[]>`
      SELECT other.user_id AS participant_id
      FROM conversation_participants me
      JOIN conversations c ON c.conversation_id = me.conversation_id
      JOIN conversation_participants other ON other.conversation_id = me.conversation_id AND other.user_id <> me.user_id
      WHERE me.user_id = ${userId}::uuid AND c.kind = 'direct' AND ${REQUEST_RECEIVED}
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
    liveId: string | null;
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

  // `ILIKE` avec `%`, `_` et `\` échappés ; demandes refusées par `userId` exclues (jamais remises).
  async searchMessages(userId: string, query: string, limit: number, hiddenSenderIds: string[] = []): Promise<Message[]> {
    const pattern = `%${query.replace(/[\\%_]/g, (c) => `\\${c}`)}%`;
    const rows = await this.prisma.$queryRaw<{ message_id: string }[]>`
      SELECT m.message_id::text AS message_id
      FROM messages m
      JOIN conversation_participants p ON p.conversation_id = m.conversation_id AND p.user_id = ${userId}::uuid
      JOIN conversations c ON c.conversation_id = m.conversation_id
      WHERE m.content ILIKE ${pattern} AND m.event IS NULL
        AND (c.kind = 'direct' OR m.sender_id <> ALL(${hiddenSenderIds}::uuid[]))
        AND m.message_id > COALESCE(p.cleared_up_to_message_id, ${ZERO})
        AND NOT (c.declined_at IS NOT NULL AND c.request_sender_id IS DISTINCT FROM ${userId}::uuid)
      ORDER BY m.message_id DESC
      LIMIT ${limit}`;
    if (rows.length === 0) return [];
    const messages = await this.prisma.message.findMany({ where: { id: { in: rows.map((r) => r.message_id) } }, select: messageSelect });
    return messages.sort((a, b) => (a.id < b.id ? 1 : -1));
  }

  private addMessageNow(input: {
    conversationId: string;
    senderId: string;
    content: string;
    sharedVideoId: string | null;
    storyId: string | null;
    liveId: string | null;
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
          liveId: input.liveId,
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

  async countUnreadConversations(userId: string, hiddenSenderIds: string[] = []): Promise<number> {
    const [row] = await this.prisma.$queryRaw<{ count: number }[]>`
      SELECT count(*)::int AS count FROM conversation_participants me
      JOIN conversations c ON c.conversation_id = me.conversation_id
      WHERE me.user_id = ${userId}::uuid AND c.accepted_at IS NOT NULL AND EXISTS (
        SELECT 1 FROM messages m
        WHERE m.conversation_id = me.conversation_id AND ${unread(hiddenSenderIds, Prisma.sql`m`)})`;
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
    { listed, before, hidden }: { listed: boolean; before: string | null; hidden: string[] },
    limit: number,
  ): Promise<ConversationView[]> {
    const list = !listed
      ? Prisma.empty
      : before
        ? Prisma.sql`AND last.message_id IS NOT NULL AND last.message_id < ${before}::uuid`
        : Prisma.sql`AND last.message_id IS NOT NULL`;
    const rows = await this.prisma.$queryRaw<ViewRow[]>`
      SELECT c.conversation_id AS id, c.created_at, c.kind, c.name, c.request_sender_id, c.accepted_at, c.declined_at,
             other.user_id AS participant_id, other.last_read_message_id AS participant_last_read,
             last.message_id AS last_id, last.sender_id AS last_sender_id, last.content AS last_content,
             last.shared_video_id AS last_shared_video_id, last.story_id AS last_story_id, last.live_id AS last_live_id,
             last.event AS last_event, last.event_user_id AS last_event_user_id, last.created_at AS last_created_at,
             (SELECT count(*)::int FROM messages u WHERE u.conversation_id = c.conversation_id AND ${unread(hidden, Prisma.sql`u`)}) AS unread_count,
             CASE WHEN c.accepted_at IS NULL
               THEN (SELECT count(*)::int FROM messages o WHERE o.conversation_id = c.conversation_id AND o.sender_id = me.user_id)
               ELSE 0 END AS own_count
      FROM conversation_participants me
      JOIN conversations c ON c.conversation_id = me.conversation_id
      LEFT JOIN conversation_participants other
        ON c.kind = 'direct' AND other.conversation_id = me.conversation_id AND other.user_id <> me.user_id
      LEFT JOIN LATERAL (
        SELECT m.message_id, m.sender_id, m.content, m.shared_video_id, m.story_id, m.live_id, m.event, m.event_user_id, m.created_at
        FROM messages m
        WHERE m.conversation_id = c.conversation_id AND m.message_id > COALESCE(me.cleared_up_to_message_id, ${ZERO})
          AND (c.kind = 'direct' OR m.sender_id <> ALL(${hidden}::uuid[]))
        ORDER BY m.message_id DESC LIMIT 1
      ) last ON true
      WHERE me.user_id = ${userId}::uuid AND (c.kind = 'group' OR other.user_id IS NOT NULL) AND ${filter} ${list}
      ORDER BY last.message_id DESC NULLS LAST
      LIMIT ${limit}`;
    return rows.map((row) => ({
      id: row.id,
      createdAt: row.created_at,
      kind: row.kind,
      name: row.name,
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
            liveId: row.last_live_id,
            event: row.last_event,
            eventUserId: row.last_event_user_id,
            createdAt: row.last_created_at!,
          }
        : null,
      unreadCount: row.unread_count,
      participantLastReadMessageId: row.participant_last_read,
      ownMessageCount: row.own_count,
    }));
  }
}
