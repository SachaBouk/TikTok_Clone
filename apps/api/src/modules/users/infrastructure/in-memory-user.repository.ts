import type { ProfileChanges, User } from '../domain/user';
import { UsernameTakenError } from '../domain/user.errors';
import { UserRepository } from '../domain/user.repository';

// Adaptateur en mémoire du port, pour tester le service sans base de données (ADR-003).
export class InMemoryUserRepository extends UserRepository {
  private readonly users = new Map<string, User>();

  constructor(users: User[] = []) {
    super();
    for (const user of users) this.users.set(user.id, user);
  }

  async findById(id: string): Promise<User | null> {
    return this.users.get(id) ?? null;
  }

  async findByUsername(username: string): Promise<User | null> {
    for (const user of this.users.values()) {
      if (user.username === username) return user;
    }
    return null;
  }

  async findByIds(ids: string[]): Promise<User[]> {
    return ids.flatMap((id) => {
      const user = this.users.get(id);
      return user ? [user] : [];
    });
  }

  async update(id: string, changes: ProfileChanges): Promise<User | null> {
    const user = this.users.get(id);
    if (!user) return null;
    if (changes.username !== undefined) {
      const owner = await this.findByUsername(changes.username);
      if (owner && owner.id !== id) throw new UsernameTakenError(changes.username);
    }
    const updated = { ...user, ...changes };
    this.users.set(id, updated);
    return updated;
  }

  async delete(id: string): Promise<boolean> {
    return this.users.delete(id);
  }

  async search(query: string | null, beforeId: string | null, limit: number): Promise<User[]> {
    const needle = query?.toLowerCase();
    return [...this.users.values()]
      .filter((user) => !beforeId || user.id < beforeId)
      .filter(
        (user) => !needle || user.username.toLowerCase().includes(needle) || user.displayName.toLowerCase().includes(needle) || user.id === needle,
      )
      .sort((a, b) => (a.id < b.id ? 1 : -1))
      .slice(0, limit);
  }

  async searchPublic(query: string, excludedIds: string[], offset: number, limit: number): Promise<User[]> {
    const needle = query.toLowerCase();
    const excluded = new Set(excludedIds);
    const rank = (user: User) => (user.username === needle ? 2 : user.username.startsWith(needle) ? 1 : 0);
    return [...this.users.values()]
      .filter((user) => !excluded.has(user.id))
      .filter((user) => user.username.toLowerCase().includes(needle) || user.displayName.toLowerCase().includes(needle))
      .sort((a, b) => rank(b) - rank(a) || b.followersCount - a.followersCount || (a.id < b.id ? 1 : -1))
      .slice(offset, offset + limit);
  }

  async count(createdSince: Date | null): Promise<number> {
    return [...this.users.values()].filter((user) => !createdSince || user.createdAt >= createdSince).length;
  }

  // Reproduit le trigger des compteurs de follow de la base (migration interaction_counters), pour les tests.
  adjustCounter(id: string, counter: 'followersCount' | 'followingCount', delta: number) {
    const user = this.users.get(id);
    if (user) user[counter] = Math.max(0, user[counter] + delta);
  }
}
