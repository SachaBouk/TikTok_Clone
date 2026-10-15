// Port des centres d'intérêt d'un compte (ADR-055).
export abstract class InterestRepository {
  // Codes enregistrés, dans un ordre quelconque (catalogue actuel ou non).
  abstract findCodes(userId: string): Promise<string[]>;
  // Remplace la liste (les codes gardés conservent leur date). Renvoie false si le compte n'existe pas.
  abstract replace(userId: string, codes: string[]): Promise<boolean>;
}
