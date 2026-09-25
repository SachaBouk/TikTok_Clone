import { AccountContentCleanup } from '../domain/account-content-cleanup';

// Adaptateur en mémoire pour les tests : garde les comptes dont le nettoyage a été programmé.
export class InMemoryAccountContentCleanup extends AccountContentCleanup {
  readonly scheduled: string[] = [];

  async scheduleCleanup(userId: string): Promise<void> {
    this.scheduled.push(userId);
  }
}
