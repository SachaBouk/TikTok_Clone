import { Injectable } from '@nestjs/common';
import { Prisma } from '../../../generated/prisma/client';
import { PrismaService } from '../../../database/prisma.service';
import { InterestRepository } from '../domain/interest.repository';

@Injectable()
export class PrismaInterestRepository extends InterestRepository {
  constructor(private readonly prisma: PrismaService) {
    super();
  }

  async findCodes(userId: string): Promise<string[]> {
    const rows = await this.prisma.userInterest.findMany({ where: { userId }, select: { interestCode: true } });
    return rows.map((row) => row.interestCode);
  }

  // Une transaction : les codes retirés sont supprimés, les nouveaux ajoutés, les autres gardent leur date.
  async replace(userId: string, codes: string[]): Promise<boolean> {
    try {
      await this.prisma.$transaction([
        this.prisma.userInterest.deleteMany({ where: { userId, interestCode: { notIn: codes } } }),
        this.prisma.userInterest.createMany({ data: codes.map((interestCode) => ({ userId, interestCode })), skipDuplicates: true }),
      ]);
      return true;
    } catch (error) {
      // Compte supprimé entre-temps : la clé étrangère refuse l'ajout.
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2003') return false;
      throw error;
    }
  }
}
