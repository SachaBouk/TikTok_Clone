import type { ProfileChanges, User } from './user';

// Port (ADR-003). Classe abstraite plutôt qu'interface : elle existe à l'exécution,
// donc sert directement de jeton d'injection NestJS, sans que le domaine importe NestJS.
export abstract class UserRepository {
  abstract findById(id: string): Promise<User | null>;
  abstract findByUsername(username: string): Promise<User | null>;
  // Comptes existants parmi `ids`, dans un ordre quelconque.
  abstract findByIds(ids: string[]): Promise<User[]>;
  // Renvoie le compte modifié, ou null s'il n'existe pas. Lève UsernameTakenError si le pseudo est pris.
  abstract update(id: string, changes: ProfileChanges): Promise<User | null>;
  // Renvoie false si le compte n'existe pas.
  abstract delete(id: string): Promise<boolean>;
}
