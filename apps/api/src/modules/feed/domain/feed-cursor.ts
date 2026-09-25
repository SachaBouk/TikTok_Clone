// Position dans une session de scroll : quelle photo du catalogue, quel ordre (graine), où.
// Encodée en base64url et opaque pour l'app, qui la renvoie telle quelle.
export interface FeedPosition {
  snapshotId: string;
  seed: number;
  offset: number;
}

export class InvalidFeedCursorError extends Error {
  constructor() {
    super('Curseur de feed invalide');
    this.name = 'InvalidFeedCursorError';
  }
}

export function encodeCursor({ snapshotId, seed, offset }: FeedPosition): string {
  return Buffer.from(JSON.stringify({ s: snapshotId, r: seed, o: offset })).toString('base64url');
}

export function decodeCursor(cursor: string): FeedPosition {
  let raw: unknown;
  try {
    raw = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8'));
  } catch {
    throw new InvalidFeedCursorError();
  }
  const { s, r, o } = (raw ?? {}) as Record<string, unknown>;
  if (typeof s !== 'string' || !Number.isInteger(r) || !Number.isInteger(o) || (o as number) < 0) {
    throw new InvalidFeedCursorError();
  }
  return { snapshotId: s, seed: r as number, offset: o as number };
}
