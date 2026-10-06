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
  // Backoffice (ADR-004) : comptes dont le pseudo ou le nom contient `query` (sans tenir compte de la casse),
  // ou dont l'identifiant vaut `query` ; tous si `query` est nul. Du plus récent au plus ancien (identifiants
  // UUID v7, ordonnés dans le temps), strictement avant `beforeId` s'il est donné.
  abstract search(query: string | null, beforeId: string | null, limit: number): Promise<User[]>;
  // Recherche publique (ADR-049) : comptes dont le pseudo ou le nom contient `query` (sans tenir compte de la casse),
  // hors `excludedIds`. Classement : pseudo identique, pseudo qui commence par `query`, puis abonnés décroissants,
  // puis identifiant décroissant. `offset` premiers résultats sautés.
  abstract searchPublic(query: string, excludedIds: string[], offset: number, limit: number): Promise<User[]>;
  // Nombre de comptes, créés depuis `createdSince` s'il est donné.
  abstract count(createdSince: Date | null): Promise<number>;
}
