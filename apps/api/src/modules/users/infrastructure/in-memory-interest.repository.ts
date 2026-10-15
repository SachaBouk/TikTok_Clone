import { InterestRepository } from '../domain/interest.repository';

// Adaptateur en mémoire du port, pour les tests du service. `knownUserIds` vide : tous les comptes existent.
export class InMemoryInterestRepository extends InterestRepository {
  readonly codes = new Map<string, Set<string>>();

  constructor(private readonly knownUserIds: ReadonlySet<string> | null = null) {
    super();
  }

  async findCodes(userId: string): Promise<string[]> {
    return [...(this.codes.get(userId) ?? [])];
  }

  async replace(userId: string, codes: string[]): Promise<boolean> {
    if (this.knownUserIds && !this.knownUserIds.has(userId)) return false;
    this.codes.set(userId, new Set(codes));
    return true;
  }
}
