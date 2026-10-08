import { randomBytes } from 'node:crypto';

// Identifiant UUID v7 (RFC 9562 : 48 bits de millisecondes, puis aléa), ordonné dans le temps comme ceux que Prisma
// génère. Choisi par le service avant la création : la clé d'une photo (`<storyId>/photo.jpg`) en dépend.
export function newStoryId(now: number = Date.now()): string {
  const bytes = randomBytes(16);
  bytes.writeUIntBE(now, 0, 6);
  bytes[6] = (bytes[6] & 0x0f) | 0x70;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}
