// Recherche de comptes (ADR-049).

// Texte cherché : 1 à 50 caractères (« @ » initial ignoré).
export const MAX_SEARCH_QUERY_LENGTH = 50;

export const DEFAULT_SEARCH_PAGE_SIZE = 20;
export const MAX_SEARCH_PAGE_SIZE = 50;
// Résultats au plus par recherche : au-delà, il vaut mieux préciser le texte cherché.
export const MAX_SEARCH_RESULTS = 100;

export class InvalidSearchCursorError extends Error {
  constructor() {
    super('Curseur de recherche invalide');
    this.name = 'InvalidSearchCursorError';
  }
}

// Curseur opaque pour l'app : position dans le classement (base64url).
export function encodeSearchCursor(offset: number): string {
  return Buffer.from(JSON.stringify({ o: offset })).toString('base64url');
}

// Lève InvalidSearchCursorError si le curseur n'a pas été produit par l'API.
export function decodeSearchCursor(cursor: string): number {
  let raw: unknown;
  try {
    raw = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8'));
  } catch {
    throw new InvalidSearchCursorError();
  }
  const { o } = (raw ?? {}) as Record<string, unknown>;
  if (!Number.isSafeInteger(o) || (o as number) < 0 || (o as number) >= MAX_SEARCH_RESULTS) throw new InvalidSearchCursorError();
  return o as number;
}

// Texte cherché nettoyé : espaces autour et « @ » initial retirés. Vide : rien à chercher.
export function normalizeSearchQuery(query: string): string {
  return query.trim().replace(/^@/, '').trim().slice(0, MAX_SEARCH_QUERY_LENGTH);
}
