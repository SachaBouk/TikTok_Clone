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

  // Reproduit le trigger des compteurs de follow de la base (migration interaction_counters), pour les tests.
  adjustCounter(id: string, counter: 'followersCount' | 'followingCount', delta: number) {
    const user = this.users.get(id);
    if (user) user[counter] = Math.max(0, user[counter] + delta);
  }
}
