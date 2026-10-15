import { randomUUID } from 'node:crypto';
import type { AccountSuspension, AuthAccount, NewAccount } from '../domain/auth-account';
import { AuthAccountRepository } from '../domain/auth-account.repository';
import { EmailAlreadyUsedError, UsernameAlreadyUsedError } from '../domain/auth.errors';

// Adaptateur en mémoire pour les tests : reproduit les contraintes d'unicité de la base.
export class InMemoryAuthAccountRepository extends AuthAccountRepository {
  readonly accounts: (NewAccount & { id: string })[] = [];
  // Rôle `admin`, attribué hors de l'API (script `admin:grant`).
  readonly adminIds = new Set<string>();
  readonly suspensions = new Map<string, AccountSuspension>();

  async findByEmail(email: string): Promise<AuthAccount | null> {
    return toAuthAccount(this.accounts.find((a) => a.email === email));
  }

  async findByUsername(username: string): Promise<AuthAccount | null> {
    return toAuthAccount(this.accounts.find((a) => a.username === username));
  }

  async findByAppleSub(appleSub: string): Promise<AuthAccount | null> {
    return toAuthAccount(this.accounts.find((a) => a.appleSub === appleSub));
  }

  async create(account: NewAccount): Promise<AuthAccount> {
    if (account.email && this.accounts.some((a) => a.email === account.email)) throw new EmailAlreadyUsedError();
    if (this.accounts.some((a) => a.username === account.username)) throw new UsernameAlreadyUsedError(account.username);
    const created = { ...account, id: randomUUID() };
    this.accounts.push(created);
    return { id: created.id, passwordHash: created.passwordHash };
  }

  async findAdminIds(ids: string[]): Promise<Set<string>> {
    return new Set(ids.filter((id) => this.adminIds.has(id)));
  }

  async findSuspensions(ids: string[]): Promise<Map<string, AccountSuspension>> {
    return new Map(ids.flatMap((id) => (this.suspensions.has(id) ? [[id, this.suspensions.get(id)!] as const] : [])));
  }

  async suspend(suspension: AccountSuspension): Promise<AccountSuspension | null> {
    if (!this.accounts.some((a) => a.id === suspension.userId)) return null;
    const current = this.suspensions.get(suspension.userId) ?? suspension;
    this.suspensions.set(suspension.userId, current);
    return current;
  }

  async liftSuspension(userId: string): Promise<void> {
    this.suspensions.delete(userId);
  }

  async listSuspendedIds(): Promise<string[]> {
    return [...this.suspensions.keys()];
  }

  async listSuspended(afterUserId: string | null, limit: number): Promise<string[]> {
    const ordered = [...this.suspensions.values()].sort(
      (a, b) => b.suspendedAt.getTime() - a.suspendedAt.getTime() || (a.userId < b.userId ? 1 : a.userId > b.userId ? -1 : 0),
    );
    let start = 0;
    if (afterUserId) {
      start = ordered.findIndex((s) => s.userId === afterUserId) + 1;
      if (start === 0) return [];
    }
    return ordered.slice(start, start + limit).map((s) => s.userId);
  }

  async countSuspended(): Promise<number> {
    return this.suspensions.size;
  }
}

function toAuthAccount(account: (NewAccount & { id: string }) | undefined): AuthAccount | null {
  return account ? { id: account.id, passwordHash: account.passwordHash } : null;
}
