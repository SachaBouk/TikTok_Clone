import { USERNAME_PATTERN } from '../../users/domain/profile-rules';

// Mentions dans un commentaire (ADR-060) : « @pseudo », ni précédé d'une lettre, d'un chiffre, de « _ », « . » ou
// « @ » (une adresse email n'est pas une mention). Même règle dans l'app (`MentionRules.swift`).
const MENTION = /(?<![\p{L}\p{N}_.@])@([A-Za-z0-9._]{2,24})/gu;

// Comptes prévenus au plus par commentaire ; pseudos lus au plus (les autres ne sont pas résolus).
export const MAX_MENTIONS_NOTIFIED = 5;
export const MAX_MENTIONS_READ = 20;

// Pseudos mentionnés, en minuscules, sans doublon, dans l'ordre du texte. Un point final (« merci @ines. ») ne fait pas
// partie du pseudo.
export function extractMentions(text: string): string[] {
  const found: string[] = [];
  for (const match of text.matchAll(MENTION)) {
    const username = match[1].toLowerCase().replace(/\.+$/, '');
    if (USERNAME_PATTERN.test(username) && !found.includes(username)) found.push(username);
    if (found.length === MAX_MENTIONS_READ) break;
  }
  return found;
}
