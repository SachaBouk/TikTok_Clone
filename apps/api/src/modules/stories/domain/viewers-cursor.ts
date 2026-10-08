import type { StoryViewPosition } from './story';

// Curseur opaque (base64url) de la liste des personnes qui ont vu une story : date de la vue et compte.
export function encodeViewersCursor(position: StoryViewPosition): string {
  return Buffer.from(JSON.stringify([position.viewedAt.toISOString(), position.userId])).toString('base64url');
}

// Null si le curseur est mal formé.
export function decodeViewersCursor(cursor: string): StoryViewPosition | null {
  try {
    const value: unknown = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8'));
    if (!Array.isArray(value) || value.length !== 2 || typeof value[0] !== 'string' || typeof value[1] !== 'string') return null;
    const viewedAt = new Date(value[0]);
    if (Number.isNaN(viewedAt.getTime()) || value[1].length === 0 || value[1].length > 64) return null;
    return { viewedAt, userId: value[1] };
  } catch {
    return null;
  }
}
