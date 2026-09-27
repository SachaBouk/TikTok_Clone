import { randomUUID } from 'node:crypto';
import type { AuthAccount, NewAccount } from '../domain/auth-account';
import { AuthAccountRepository } from '../domain/auth-account.repository';
import { EmailAlreadyUsedError, UsernameAlreadyUsedError } from '../domain/auth.errors';

// Adaptateur en mémoire pour les tests : reproduit les contraintes d'unicité de la base.
export class InMemoryAuthAccountRepository extends AuthAccountRepository {
  readonly accounts: (NewAccount & { id: string })[] = [];
  // Rôle `admin`, attribué hors de l'API (script `admin:grant`).
  readonly adminIds = new Set<string>();

  async findByEmail(email: string): Promise<AuthAccount | null> {
    return toAuthAccount(this.accounts.find((a) => a.email === email));
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
}

function toAuthAccount(account: (NewAccount & { id: string }) | undefined): AuthAccount | null {
  return account ? { id: account.id, passwordHash: account.passwordHash } : null;
}
