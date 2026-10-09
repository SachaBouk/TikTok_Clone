import { Injectable } from '@nestjs/common';
import { Prisma } from '../../../generated/prisma/client';
import { PrismaService } from '../../../database/prisma.service';
import type { Live, LiveEndReason, LiveMessage } from '../domain/live';
import { LiveRepository, type NewLive, type NewLiveMessage } from '../domain/live.repository';

const liveSelect = {
  id: true,
  userId: true,
  title: true,
  status: true,
  startedAt: true,
  endedAt: true,
  endReason: true,
  peakViewers: true,
  heartsCount: true,
  giftsCount: true,
  giftsAmount: true,
} as const;

const messageSelect = { id: true, liveId: true, userId: true, content: true, createdAt: true } as const;

// Tables lives, live_viewers, live_messages (ADR-053). Un seul live en cours par compte (index unique partiel).
@Injectable()
export class PrismaLiveRepository extends LiveRepository {
  constructor(private readonly prisma: PrismaService) {
    super();
  }

  async create(live: NewLive): Promise<Live | null> {
    try {
      return await this.prisma.live.create({
        data: { id: live.id, userId: live.userId, title: live.title, startedAt: live.startedAt },
        select: liveSelect,
      });
    } catch (error) {
      // Index `lives_in_progress_key` : le compte a déjà un live en cours.
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') return null;
      throw error;
    }
  }

  findById(id: string): Promise<Live | null> {
    return this.prisma.live.findUnique({ where: { id }, select: liveSelect });
  }

  findByIds(ids: string[]): Promise<Live[]> {
    return ids.length === 0 ? Promise.resolve([]) : this.prisma.live.findMany({ where: { id: { in: ids } }, select: liveSelect });
  }

  findInProgressByUser(userId: string): Promise<Live | null> {
    return this.prisma.live.findFirst({ where: { userId, status: 'live' }, select: liveSelect });
  }

  findInProgressByUsers(userIds: string[]): Promise<Live[]> {
    if (userIds.length === 0) return Promise.resolve([]);
    return this.prisma.live.findMany({
      where: { userId: { in: userIds }, status: 'live' },
      orderBy: { startedAt: 'desc' },
      select: liveSelect,
    });
  }

  // Transition atomique `live` → `ended` : deux fins simultanées n'en enregistrent qu'une.
  async end(id: string, reason: LiveEndReason, at: Date): Promise<Live | null> {
    const { count } = await this.prisma.live.updateMany({
      where: { id, status: 'live' },
      data: { status: 'ended', endedAt: at, endReason: reason },
    });
    return count === 0 ? null : this.findById(id);
  }

  async recordViewer(liveId: string, identity: string, at: Date): Promise<void> {
    await this.prisma.liveViewer.createMany({ data: [{ liveId, identity, joinedAt: at }], skipDuplicates: true });
  }

  async raisePeakViewers(liveId: string, count: number): Promise<void> {
    await this.prisma.live.updateMany({ where: { id: liveId, peakViewers: { lt: count } }, data: { peakViewers: count } });
  }

  countViewers(liveId: string, excludedIdentity: string): Promise<number> {
    return this.prisma.liveViewer.count({ where: { liveId, identity: { not: excludedIdentity } } });
  }

  async addHearts(liveId: string, count: number): Promise<number> {
    const live = await this.prisma.live.update({ where: { id: liveId }, data: { heartsCount: { increment: count } }, select: { heartsCount: true } });
    return live.heartsCount;
  }

  addGift(liveId: string, amount: number): Promise<{ giftsCount: number; giftsAmount: number }> {
    return this.prisma.live.update({
      where: { id: liveId },
      data: { giftsCount: { increment: 1 }, giftsAmount: { increment: amount } },
      select: { giftsCount: true, giftsAmount: true },
    });
  }

  addMessage(message: NewLiveMessage): Promise<LiveMessage> {
    return this.prisma.liveMessage.create({ data: message, select: messageSelect });
  }

  findMessage(id: string): Promise<LiveMessage | null> {
    return this.prisma.liveMessage.findUnique({ where: { id }, select: messageSelect });
  }

  async deleteMessage(id: string): Promise<void> {
    await this.prisma.liveMessage.deleteMany({ where: { id } });
  }

  // Les plus récents (index (live_id, live_message_id)), remis du plus ancien au plus récent.
  async listRecentMessages(liveId: string, limit: number, excludedUserIds: string[]): Promise<LiveMessage[]> {
    const rows = await this.prisma.liveMessage.findMany({
      where: { liveId, ...(excludedUserIds.length ? { userId: { notIn: excludedUserIds } } : {}) },
      orderBy: { id: 'desc' },
      take: limit,
      select: messageSelect,
    });
    return rows.reverse();
  }

  async deleteMessages(liveId: string): Promise<void> {
    await this.prisma.liveMessage.deleteMany({ where: { liveId } });
  }

  findInProgress(limit: number): Promise<Live[]> {
    return this.prisma.live.findMany({ where: { status: 'live' }, orderBy: { startedAt: 'asc' }, take: limit, select: liveSelect });
  }
}
