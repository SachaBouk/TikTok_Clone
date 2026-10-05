// Règles du profil public (ADR-016 : nom, pseudo, photo, bio), partagées par le service, la validation
// des requêtes et l'inscription (module auth, qui crée les comptes).

// Pseudo : minuscules, chiffres, points et underscores, comme sur TikTok.
export const USERNAME_PATTERN = /^[a-z0-9._]{2,24}$/;
// Pseudos qui entreraient en conflit avec des routes (`GET /users/me`).
export const RESERVED_USERNAMES: ReadonlySet<string> = new Set(['me']);

export const MAX_DISPLAY_NAME_LENGTH = 50;
// Comme sur TikTok.
export const MAX_BIO_LENGTH = 80;

import { type ImageDimensions, readJpegDimensions, readPngDimensions } from './image-dimensions';

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
// Dimensions acceptées (ADR-046) : un carré de 64 à 2048 px. L'app envoie 512 px ; la marge permet de la faire
// évoluer, et la borne haute épargne aux lecteurs une image géante à décompresser.
export const AVATAR_MIN_DIMENSION = 64;
export const AVATAR_MAX_DIMENSION = 2048;
// Octets lus au début du fichier pour la signature et les dimensions : assez pour les segments d'un JPEG (EXIF…)
// avant son marqueur SOF ; au-delà, l'image est refusée.
export const AVATAR_HEADER_LENGTH = 64 * 1024;

const DIMENSION_READERS: Record<AvatarContentType, (head: Uint8Array) => ImageDimensions | null> = {
  'image/jpeg': readJpegDimensions,
  'image/png': readPngDimensions,
};

export function isValidUsername(username: string): boolean {
  return USERNAME_PATTERN.test(username) && !RESERVED_USERNAMES.has(username);
}

export function isAvatarContentType(contentType: string | null): contentType is AvatarContentType {
  return (AVATAR_CONTENT_TYPES as readonly (string | null)[]).includes(contentType);
}

export function matchesAvatarSignature(contentType: AvatarContentType, head: Uint8Array): boolean {
  return AVATAR_SIGNATURES[contentType].every((byte, index) => head[index] === byte);
}

// Dimensions lues dans les premiers octets (`AVATAR_HEADER_LENGTH`), ou null si elles sont illisibles.
export function avatarDimensions(contentType: AvatarContentType, head: Uint8Array): ImageDimensions | null {
  return DIMENSION_READERS[contentType](head);
}

export function isValidAvatarDimensions({ width, height }: ImageDimensions): boolean {
  return width === height && width >= AVATAR_MIN_DIMENSION && width <= AVATAR_MAX_DIMENSION;
}

// Contenu réel d'une photo envoyée : signature du type déclaré, puis carré aux dimensions acceptées.
export function isValidAvatarContent(contentType: AvatarContentType, head: Uint8Array): boolean {
  if (!matchesAvatarSignature(contentType, head)) return false;
  const dimensions = avatarDimensions(contentType, head);
  return dimensions !== null && isValidAvatarDimensions(dimensions);
}

// Objets de la photo de profil d'un compte : tous sous son préfixe, pour les retrouver et les supprimer.
export function avatarPrefix(userId: string): string {
  return `${userId}/`;
}

export function avatarKey(userId: string, avatarId: string): string {
  return `${avatarPrefix(userId)}${avatarId}`;
}
