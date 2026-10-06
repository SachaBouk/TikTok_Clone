// Hashtags des descriptions (ADR-049). Règle d'extraction écrite aussi dans l'app (`HashtagRules.swift`) et dans le
// SQL de la migration `search_hashtags` (remplissage des vidéos déjà publiées) : les garder alignées.
// - description en NFC ;
// - « # » suivi de 1 à 50 lettres, chiffres ou « _ », ni précédé ni suivi d'un tel caractère (au-delà de 50, ce
//   n'est pas un hashtag). Lettres (\p{L}, \p{Nl}) et chiffres décimaux (\p{Nd}) : la classe [[:alnum:]] de
//   PostgreSQL (ni « ½ » ni « ² ») ;
// - au moins une lettre ou un chiffre ;
// - nom en minuscules, accents gardés (#été ≠ #ete) ;
// - 20 hashtags distincts au plus par vidéo, dans l'ordre d'apparition.

export const MAX_HASHTAG_LENGTH = 50;
export const MAX_HASHTAGS_PER_VIDEO = 20;

// Suggestions et recherche de hashtags (ADR-049).
export const DEFAULT_HASHTAG_SUGGESTIONS = 10;
export const MAX_HASHTAG_SUGGESTIONS = 20;
export const TRENDING_HASHTAGS = 10;
// Fenêtre des hashtags tendance : vidéos publiées pendant cette durée.
export const TRENDING_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;

const HASHTAG_PATTERN = /(?<![\p{L}\p{Nl}\p{Nd}_])#([\p{L}\p{Nl}\p{Nd}_]{1,50})(?![\p{L}\p{Nl}\p{Nd}_])/gu;
const NAME_PATTERN = /^[\p{L}\p{Nl}\p{Nd}_]{1,50}$/u;
const HAS_LETTER_OR_DIGIT = /[\p{L}\p{Nl}\p{Nd}]/u;

export interface Hashtag {
  name: string;
  // Vidéos publiées portant ce hashtag (comptes masqués compris).
  videosCount: number;
}

// Position dans la page d'un hashtag, de la vidéo publiée la plus récente à la plus ancienne.
export interface HashtagVideoPosition {
  videoId: string;
  // Date de publication de la vidéo (passage en `ready`).
  taggedAt: Date;
}

// Hashtags distincts d'une description, dans l'ordre d'apparition.
export function extractHashtags(description: string | null): string[] {
  if (!description) return [];
  const names = new Set<string>();
  for (const [, raw] of description.normalize('NFC').matchAll(HASHTAG_PATTERN)) {
    if (!HAS_LETTER_OR_DIGIT.test(raw)) continue;
    names.add(raw.toLowerCase());
    if (names.size === MAX_HASHTAGS_PER_VIDEO) break;
  }
  return [...names];
}

// Nom de hashtag tel qu'il est stocké, à partir d'un paramètre (« #Été » → « été ») ; null s'il n'est pas valide.
export function normalizeHashtagName(input: string): string | null {
  const name = input.trim().replace(/^#/, '').normalize('NFC').toLowerCase();
  return NAME_PATTERN.test(name) && HAS_LETTER_OR_DIGIT.test(name) ? name : null;
}

// Début de nom saisi (recherche, suggestions) : « # » initial retiré, en minuscules. Vide ou invalide : null.
export function normalizeHashtagPrefix(input: string): string | null {
  const prefix = input.trim().replace(/^#/, '').normalize('NFC').toLowerCase();
  return NAME_PATTERN.test(prefix) ? prefix : null;
}
