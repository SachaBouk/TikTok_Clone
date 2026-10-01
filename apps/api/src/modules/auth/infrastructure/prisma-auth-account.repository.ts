import { Injectable } from '@nestjs/common';
import { violatedUniqueConstraint } from '../../../database/prisma-errors';
import { PrismaService } from '../../../database/prisma.service';
import type { AccountSuspension, AuthAccount, NewAccount } from '../domain/auth-account';
import { AuthAccountRepository } from '../domain/auth-account.repository';
import { EmailAlreadyUsedError, UsernameAlreadyUsedError } from '../domain/auth.errors';

const accountSelect = { id: true, passwordHash: true } as const;
const suspensionSelect = { id: true, suspendedAt: true, suspensionReason: true, suspendedById: true } as const;

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

  async findAdminIds(ids: string[]): Promise<Set<string>> {
    if (ids.length === 0) return new Set();
    const admins = await this.prisma.user.findMany({ where: { id: { in: ids }, role: 'admin' }, select: { id: true } });
    return new Set(admins.map((admin) => admin.id));
  }

  async findSuspensions(ids: string[]): Promise<Map<string, AccountSuspension>> {
    if (ids.length === 0) return new Map();
    const rows = await this.prisma.user.findMany({ where: { id: { in: ids }, suspendedAt: { not: null } }, select: suspensionSelect });
    return new Map(rows.flatMap((row) => toSuspension(row) ?? []).map((s) => [s.userId, s]));
  }

  // Une seule écriture conditionnelle : deux suspensions simultanées gardent la première.
  async suspend(suspension: AccountSuspension): Promise<AccountSuspension | null> {
    await this.prisma.user.updateMany({
      where: { id: suspension.userId, suspendedAt: null },
      data: { suspendedAt: suspension.suspendedAt, suspensionReason: suspension.reason, suspendedById: suspension.suspendedBy },
    });
    const row = await this.prisma.user.findUnique({ where: { id: suspension.userId }, select: suspensionSelect });
    return row ? toSuspension(row) : null;
  }

  async liftSuspension(userId: string): Promise<void> {
    await this.prisma.user.updateMany({ where: { id: userId }, data: { suspendedAt: null, suspensionReason: null, suspendedById: null } });
  }

  async listSuspendedIds(): Promise<string[]> {
    const rows = await this.prisma.user.findMany({ where: { suspendedAt: { not: null } }, select: { id: true } });
    return rows.map((row) => row.id);
  }

  countSuspended(): Promise<number> {
    return this.prisma.user.count({ where: { suspendedAt: { not: null } } });
  }
}

function toSuspension(row: { id: string; suspendedAt: Date | null; suspensionReason: string | null; suspendedById: string | null }): AccountSuspension | null {
  if (!row.suspendedAt || row.suspensionReason === null) return null;
  return { userId: row.id, suspendedAt: row.suspendedAt, reason: row.suspensionReason, suspendedBy: row.suspendedById };
}
