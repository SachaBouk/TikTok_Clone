import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../../database/prisma.service';
import { ModerationActionRepository } from '../domain/moderation-action.repository';
import type { ModerationAction, NewModerationAction } from '../domain/report';

const actionSelect = {
  id: true,
  adminId: true,
  adminUsername: true,
  action: true,
  targetType: true,
  targetId: true,
  targetUserId: true,
  targetUsername: true,
  reason: true,
  note: true,
  excerpt: true,
  reportsClosed: true,
  createdAt: true,
} as const;

// Table moderation_actions (ADR-038).
@Injectable()
export class PrismaModerationActionRepository extends ModerationActionRepository {
  constructor(private readonly prisma: PrismaService) {
    super();
  }

  async add(action: NewModerationAction): Promise<void> {
    await this.prisma.moderationAction.create({
      data: {
        adminId: action.adminId,
        adminUsername: action.adminUsername,
        action: action.action,
        targetType: action.target.type,
        targetId: action.target.id,
        targetUserId: action.targetUserId,
        targetUsername: action.targetUsername,
        reason: action.reason,
        note: action.note,
        excerpt: action.excerpt,
        reportsClosed: action.reportsClosed,
      },
    });
  }

  async list(filter: { targetUserId?: string }, beforeId: string | null, limit: number): Promise<ModerationAction[]> {
    const rows = await this.prisma.moderationAction.findMany({
      where: { ...(filter.targetUserId ? { targetUserId: filter.targetUserId } : {}), ...(beforeId ? { id: { lt: beforeId } } : {}) },
      orderBy: { id: 'desc' },
      take: limit,
      select: actionSelect,
    });
    return rows.map(({ targetType, targetId, ...row }) => ({ ...row, target: { type: targetType, id: targetId } }));
  }
}
