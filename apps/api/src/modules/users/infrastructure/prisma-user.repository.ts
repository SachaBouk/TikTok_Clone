import { Injectable } from '@nestjs/common';
import { violatedUniqueConstraint } from '../../../database/prisma-errors';
import { PrismaService } from '../../../database/prisma.service';
import type { ProfileChanges, User } from '../domain/user';
import { UsernameTakenError } from '../domain/user.errors';
import { UserRepository } from '../domain/user.repository';

// Ne sélectionne que les champs du type de domaine : les données d'authentification ne sortent jamais d'ici.
const userSelect = {
  id: true,
  username: true,
  displayName: true,
  avatarUrl: true,
  bio: true,
  followersCount: true,
  followingCount: true,
  createdAt: true,
} as const;

@Injectable()
export class PrismaUserRepository extends UserRepository {
  constructor(private readonly prisma: PrismaService) {
    super();
  }

  findById(id: string): Promise<User | null> {
    return this.prisma.user.findUnique({ where: { id }, select: userSelect });
  }

  findByUsername(username: string): Promise<User | null> {
    return this.prisma.user.findUnique({ where: { username }, select: userSelect });
  }

  findByIds(ids: string[]): Promise<User[]> {
    if (ids.length === 0) return Promise.resolve([]);
    return this.prisma.user.findMany({ where: { id: { in: ids } }, select: userSelect });
  }

  async update(id: string, changes: ProfileChanges): Promise<User | null> {
    try {
      // `updateMany` : pas d'exception si le compte a disparu, seulement count = 0.
      const { count } = await this.prisma.user.updateMany({ where: { id }, data: changes });
      return count === 1 ? this.findById(id) : null;
    } catch (error) {
      if (changes.username !== undefined && violatedUniqueConstraint(error)?.includes('username')) {
        throw new UsernameTakenError(changes.username);
      }
      throw error;
    }
  }

  async delete(id: string): Promise<boolean> {
    const { count } = await this.prisma.user.deleteMany({ where: { id } });
    return count === 1;
  }
}
