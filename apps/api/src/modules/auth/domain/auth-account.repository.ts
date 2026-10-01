import type { AccountSuspension, AuthAccount, NewAccount } from './auth-account';

export abstract class AuthAccountRepository {
  abstract findByEmail(email: string): Promise<AuthAccount | null>;
  abstract findByAppleSub(appleSub: string): Promise<AuthAccount | null>;
  // Lève EmailAlreadyUsedError ou UsernameAlreadyUsedError en cas de doublon.
  abstract create(account: NewAccount): Promise<AuthAccount>;
  // Administrateurs (ADR-004) parmi `ids`.
  abstract findAdminIds(ids: string[]): Promise<Set<string>>;

  // Suspensions en cours parmi `ids` (ADR-037).
  abstract findSuspensions(ids: string[]): Promise<Map<string, AccountSuspension>>;
  // Suspend le compte s'il ne l'est pas déjà. Renvoie la suspension en cours (la précédente si le compte était déjà
  // suspendu), ou null si le compte n'existe pas.
  abstract suspend(suspension: AccountSuspension): Promise<AccountSuspension | null>;
  // Idempotent.
  abstract liftSuspension(userId: string): Promise<void>;
  abstract listSuspendedIds(): Promise<string[]>;
  abstract countSuspended(): Promise<number>;
}
