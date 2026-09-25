// Règles du profil public (ADR-016 : nom, pseudo, photo, bio), partagées par le service, la validation
// des requêtes et l'inscription (module auth, qui crée les comptes).

// Pseudo : minuscules, chiffres, points et underscores, comme sur TikTok.
export const USERNAME_PATTERN = /^[a-z0-9._]{2,24}$/;
// Pseudos qui entreraient en conflit avec des routes (`GET /users/me`).
export const RESERVED_USERNAMES: ReadonlySet<string> = new Set(['me']);

export const MAX_DISPLAY_NAME_LENGTH = 50;
// Comme sur TikTok.
export const MAX_BIO_LENGTH = 80;

// Photo de profil : l'app la recadre en carré (512 px) et l'encode avant l'envoi. Pas de traitement côté serveur.
export const AVATAR_CONTENT_TYPES = ['image/jpeg', 'image/png'] as const;
export type AvatarContentType = (typeof AVATAR_CONTENT_TYPES)[number];
export const MAX_AVATAR_SIZE_BYTES = 5 * 1024 ** 2; // 5 Mio
// Un seul PUT, d'un petit fichier : une URL courte suffit.
export const AVATAR_UPLOAD_URL_TTL_SECONDS = 15 * 60;

// Premiers octets de chaque format : le contenu doit correspondre au type déclaré.
const AVATAR_SIGNATURES: Record<AvatarContentType, number[]> = {
  'image/jpeg': [0xff, 0xd8, 0xff],
  'image/png': [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
};
export const AVATAR_SIGNATURE_LENGTH = 8;

export function isValidUsername(username: string): boolean {
  return USERNAME_PATTERN.test(username) && !RESERVED_USERNAMES.has(username);
}

export function isAvatarContentType(contentType: string | null): contentType is AvatarContentType {
  return (AVATAR_CONTENT_TYPES as readonly (string | null)[]).includes(contentType);
}

export function matchesAvatarSignature(contentType: AvatarContentType, head: Uint8Array): boolean {
  return AVATAR_SIGNATURES[contentType].every((byte, index) => head[index] === byte);
}

// Objets de la photo de profil d'un compte : tous sous son préfixe, pour les retrouver et les supprimer.
export function avatarPrefix(userId: string): string {
  return `${userId}/`;
}

export function avatarKey(userId: string, avatarId: string): string {
  return `${avatarPrefix(userId)}${avatarId}`;
}
