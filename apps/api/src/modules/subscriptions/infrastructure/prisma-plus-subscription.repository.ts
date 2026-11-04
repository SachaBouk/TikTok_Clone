import { Injectable } from '@nestjs/common';
import { Prisma } from '../../../generated/prisma/client';
import { PrismaService } from '../../../database/prisma.service';
import type { PlusSubscription } from '../domain/plus-subscription';
import { PlusSubscriptionRepository } from '../domain/plus-subscription.repository';

const select = { userId: true, productId: true, period: true, expiresAt: true, willRenew: true, store: true, environment: true } as const;

@Injectable()
export class PrismaPlusSubscriptionRepository extends PlusSubscriptionRepository {
  constructor(private readonly prisma: PrismaService) {
    super();
  }

  find(userId: string): Promise<PlusSubscription | null> {
    return this.prisma.plusSubscription.findUnique({ where: { userId }, select });
  }

  async save(subscription: PlusSubscription): Promise<boolean> {
    const { userId, ...data } = subscription;
    try {
      await this.prisma.plusSubscription.upsert({ where: { userId }, create: subscription, update: data });
      return true;
    } catch (error) {
      // Compte supprimé entre-temps (clé étrangère).
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2003') return false;
      throw error;
    }
  }

  listActive(now: Date): Promise<PlusSubscription[]> {
    return this.prisma.plusSubscription.findMany({ where: { expiresAt: { gt: now } }, select });
  }
}
