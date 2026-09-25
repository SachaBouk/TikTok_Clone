import { InvalidFeedCursorError } from './feed-cursor';

// Position dans une grille du profil, triée de la plus récente à la plus ancienne : date (publication de
// la vidéo, ou republication / mise en favori) et identifiant de la vidéo, qui départage deux dates égales.
// Encodée en base64url, opaque pour l'app.
export interface ListPosition {
  at: Date;
  videoId: string;
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function encodeListCursor({ at, videoId }: ListPosition): string {
  return Buffer.from(JSON.stringify({ t: at.getTime(), v: videoId })).toString('base64url');
}

// Lève InvalidFeedCursorError si le curseur n'a pas été produit par l'API.
export function decodeListCursor(cursor: string): ListPosition {
  let raw: unknown;
  try {
    raw = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8'));
  } catch {
    throw new InvalidFeedCursorError();
  }
  const { t, v } = (raw ?? {}) as Record<string, unknown>;
  if (!Number.isSafeInteger(t) || (t as number) < 0 || typeof v !== 'string' || !UUID_PATTERN.test(v)) {
    throw new InvalidFeedCursorError();
  }
  return { at: new Date(t as number), videoId: v };
}
