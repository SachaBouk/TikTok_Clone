import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../../database/prisma.service';
import type { PushDevice } from '../domain/push';
import { PushDeviceRepository } from '../domain/push-device.repository';

const deviceSelect = { token: true, userId: true, environment: true } as const;

@Injectable()
export class PrismaPushDeviceRepository extends PushDeviceRepository {
  constructor(private readonly prisma: PrismaService) {
    super();
  }

  async register({ token, userId, environment }: PushDevice): Promise<void> {
    await this.prisma.pushDevice.upsert({ where: { token }, create: { token, userId, environment }, update: { userId, environment } });
  }

  async unregister(userId: string, token: string): Promise<void> {
    await this.prisma.pushDevice.deleteMany({ where: { token, userId } });
  }

  findByUser(userId: string): Promise<PushDevice[]> {
    return this.prisma.pushDevice.findMany({ where: { userId }, select: deviceSelect });
  }

  async remove(token: string): Promise<void> {
    await this.prisma.pushDevice.deleteMany({ where: { token } });
  }
}
