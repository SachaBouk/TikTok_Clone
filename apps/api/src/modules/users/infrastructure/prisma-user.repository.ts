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

  search(query: string | null, beforeId: string | null, limit: number): Promise<User[]> {
    const matches = query
      ? [
          { username: { contains: query, mode: 'insensitive' as const } },
          { displayName: { contains: query, mode: 'insensitive' as const } },
          // Comparer une colonne uuid à autre chose qu'un UUID ferait échouer la requête.
          ...(UUID_PATTERN.test(query) ? [{ id: query.toLowerCase() }] : []),
        ]
      : undefined;
    return this.prisma.user.findMany({
      where: { id: beforeId ? { lt: beforeId } : undefined, OR: matches },
      orderBy: { id: 'desc' },
      take: limit,
      select: userSelect,
    });
  }

  // Index trigrammes sur le pseudo et le nom (migration search_hashtags). `%`, `_` et `\` échappés pour LIKE.
  searchPublic(query: string, excludedIds: string[], offset: number, limit: number): Promise<User[]> {
    const needle = query.toLowerCase();
    const escaped = needle.replace(/[\\%_]/g, '\\$&');
    return this.prisma.$queryRaw<User[]>`
      SELECT user_id AS id, username, display_name AS "displayName", avatar_url AS "avatarUrl", bio,
             followers_count AS "followersCount", following_count AS "followingCount", created_at AS "createdAt"
      FROM users
      WHERE (username ILIKE ${`%${escaped}%`} OR display_name ILIKE ${`%${escaped}%`})
        AND user_id <> ALL(${excludedIds}::uuid[])
      ORDER BY (username = ${needle}) DESC, (username LIKE ${`${escaped}%`}) DESC, followers_count DESC, user_id DESC
      OFFSET ${offset} LIMIT ${limit}`;
  }

  count(createdSince: Date | null): Promise<number> {
    return this.prisma.user.count({ where: createdSince ? { createdAt: { gte: createdSince } } : undefined });
  }
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
