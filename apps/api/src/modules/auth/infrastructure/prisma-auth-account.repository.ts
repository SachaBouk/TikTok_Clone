import { Injectable } from '@nestjs/common';
import { violatedUniqueConstraint } from '../../../database/prisma-errors';
import { PrismaService } from '../../../database/prisma.service';
import type { AuthAccount, NewAccount } from '../domain/auth-account';
import { AuthAccountRepository } from '../domain/auth-account.repository';
import { EmailAlreadyUsedError, UsernameAlreadyUsedError } from '../domain/auth.errors';

const accountSelect = { id: true, passwordHash: true } as const;

@Injectable()
export class PrismaAuthAccountRepository extends AuthAccountRepository {
  constructor(private readonly prisma: PrismaService) {
    super();
  }

  findByEmail(email: string): Promise<AuthAccount | null> {
    return this.prisma.user.findUnique({ where: { email }, select: accountSelect });
  }

  findByAppleSub(appleSub: string): Promise<AuthAccount | null> {
    return this.prisma.user.findUnique({ where: { appleSub }, select: accountSelect });
  }

  async create(account: NewAccount): Promise<AuthAccount> {
    try {
      return await this.prisma.user.create({ data: account, select: accountSelect });
    } catch (error) {
      const constraint = violatedUniqueConstraint(error);
      if (constraint?.includes('email')) throw new EmailAlreadyUsedError();
      if (constraint?.includes('username')) throw new UsernameAlreadyUsedError(account.username);
      throw error;
    }
  }
}
