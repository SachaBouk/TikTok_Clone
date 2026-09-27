import type { AuthAccount, NewAccount } from './auth-account';

export abstract class AuthAccountRepository {
  abstract findByEmail(email: string): Promise<AuthAccount | null>;
  abstract findByAppleSub(appleSub: string): Promise<AuthAccount | null>;
  // Lève EmailAlreadyUsedError ou UsernameAlreadyUsedError en cas de doublon.
  abstract create(account: NewAccount): Promise<AuthAccount>;
  // Administrateurs (ADR-004) parmi `ids`.
  abstract findAdminIds(ids: string[]): Promise<Set<string>>;
}
