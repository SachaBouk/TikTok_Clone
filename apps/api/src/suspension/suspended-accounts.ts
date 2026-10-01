// Registre des comptes suspendus (ADR-037), partagé par les modules qui masquent leurs contenus (users, interactions,
// notifications) et par auth, qui refuse leurs requêtes. Port sans dépendance à NestJS ni à Redis : les couches
// domain/ et application/ des modules peuvent l'importer (ADR-003), comme le limiteur de débit (ADR-030).
// La base reste la source de vérité (colonnes `users.suspended_*`, propriété du module auth) ; le registre en est
// une copie dans Redis, écrite par auth à chaque suspension et reconstruite au démarrage de l'API, pour qu'aucune
// requête n'ait à lire la base pour savoir si un compte est suspendu.
// Lecture impossible (Redis indisponible) : aucun compte n'est considéré comme suspendu, et c'est journalisé.
export abstract class SuspendedAccounts {
  abstract has(userId: string): Promise<boolean>;
  abstract all(): Promise<Set<string>>;
  // Écritures : une erreur est propagée (la suspension doit être retentée).
  abstract add(userId: string): Promise<void>;
  abstract remove(userId: string): Promise<void>;
  abstract replaceAll(userIds: string[]): Promise<void>;
}
