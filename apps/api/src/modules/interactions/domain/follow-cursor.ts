import type { FollowPosition } from './interaction';
import { InvalidFollowCursorError } from './interaction.errors';

// Curseur des listes d'abonnés et d'abonnements : date du dernier follow reçu et identifiant du compte
// (départage deux follows de la même milliseconde). Encodé en base64url, opaque pour l'app.

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function encodeFollowCursor({ followedAt, userId }: FollowPosition): string {
  return Buffer.from(JSON.stringify({ t: followedAt.getTime(), u: userId })).toString('base64url');
}

export function decodeFollowCursor(cursor: string): FollowPosition {
  let raw: unknown;
  try {
    raw = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8'));
  } catch {
    throw new InvalidFollowCursorError();
  }
  const { t, u } = (raw ?? {}) as Record<string, unknown>;
  if (!Number.isSafeInteger(t) || (t as number) < 0 || typeof u !== 'string' || !UUID_PATTERN.test(u)) {
    throw new InvalidFollowCursorError();
  }
  return { followedAt: new Date(t as number), userId: u };
}
