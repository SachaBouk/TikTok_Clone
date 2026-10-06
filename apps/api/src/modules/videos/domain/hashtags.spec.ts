import { describe, expect, it } from 'vitest';
import { extractHashtags, normalizeHashtagName, normalizeHashtagPrefix } from './hashtags';

// Règle à garder alignée avec HashtagRules.swift et le SQL de la migration search_hashtags (ADR-049).
describe('extractHashtags', () => {
  it('extrait les hashtags en minuscules, accents gardés, dans l’ordre et sans doublon', () => {
    expect(extractHashtags('Été #Été #été2026 #ÉTÉ #Défi_du_Jour')).toEqual(['été', 'été2026', 'défi_du_jour']);
  });

  it('exige un « # » ni précédé ni suivi d’une lettre, d’un chiffre ou d’un « _ »', () => {
    expect(extractHashtags('a#b #x#y _#z #ok! (#paren) #fin.')).toEqual(['x', 'ok', 'paren', 'fin']);
  });

  it('exige au moins une lettre ou un chiffre', () => {
    expect(extractHashtags('# #_ #__ #__a #- #2026')).toEqual(['__a', '2026']);
  });

  it('lettres et chiffres décimaux, comme [[:alnum:]] de PostgreSQL : ni « ½ » ni « ² »', () => {
    expect(extractHashtags('#日本語 #١٢٣ #½ #x² #Ⅻ')).toEqual(['日本語', '١٢٣', 'x', 'ⅻ']);
  });

  it('ignore un mot de plus de 50 caractères', () => {
    expect(extractHashtags(`#${'a'.repeat(50)} #${'b'.repeat(51)}`)).toEqual(['a'.repeat(50)]);
  });

  it('normalise en NFC (« e » + accent combinant = « é »)', () => {
    expect(extractHashtags('#été #été')).toEqual(['été']);
  });

  it('garde 20 hashtags au plus', () => {
    const description = Array.from({ length: 25 }, (_, i) => `#tag${i}`).join(' ');
    expect(extractHashtags(description)).toHaveLength(20);
    expect(extractHashtags(description).at(-1)).toBe('tag19');
  });

  it('description vide ou nulle : aucun', () => {
    expect(extractHashtags(null)).toEqual([]);
    expect(extractHashtags('Sans hashtag')).toEqual([]);
  });
});

describe('noms et préfixes saisis', () => {
  it('normalise un nom de page (« # » initial, casse)', () => {
    expect(normalizeHashtagName('#Été')).toBe('été');
    expect(normalizeHashtagName('été2026')).toBe('été2026');
    expect(normalizeHashtagName('a b')).toBeNull();
    expect(normalizeHashtagName('__')).toBeNull();
    expect(normalizeHashtagName('a'.repeat(51))).toBeNull();
  });

  it('accepte un préfixe fait de « _ », refuse le vide', () => {
    expect(normalizeHashtagPrefix('#Dé')).toBe('dé');
    expect(normalizeHashtagPrefix('_')).toBe('_');
    expect(normalizeHashtagPrefix('#')).toBeNull();
    expect(normalizeHashtagPrefix('a%')).toBeNull();
  });
});
