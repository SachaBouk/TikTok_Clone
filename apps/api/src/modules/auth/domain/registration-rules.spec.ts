import { describe, expect, it } from 'vitest';
import { ageOn, isValidPassword, parseBirthDate } from './registration-rules';

describe('règles de l’inscription (ADR-055)', () => {
  const now = new Date('2026-10-15T12:00:00Z');

  it('lit une date du calendrier, en refusant les dates impossibles ou hors bornes', () => {
    expect(parseBirthDate('2000-02-29', now)).toEqual(new Date('2000-02-29T00:00:00Z'));
    expect(parseBirthDate('2001-02-29', now)).toBeNull();
    expect(parseBirthDate('2026-10-16', now)).toBeNull();
    expect(parseBirthDate('1900-01-01', now)).not.toBeNull();
    expect(parseBirthDate('1899-12-31', now)).toBeNull();
    expect(parseBirthDate('2000-2-1', now)).toBeNull();
  });

  it('compte les années révolues', () => {
    expect(ageOn(new Date('2013-10-15T00:00:00Z'), now)).toBe(13);
    expect(ageOn(new Date('2013-10-16T00:00:00Z'), now)).toBe(12);
    // 29 février : un an de plus le 1er mars d'une année non bissextile.
    expect(ageOn(new Date('2012-02-29T00:00:00Z'), new Date('2025-02-28T00:00:00Z'))).toBe(12);
    expect(ageOn(new Date('2012-02-29T00:00:00Z'), new Date('2025-03-01T00:00:00Z'))).toBe(13);
  });

  it('mot de passe : 8 à 128 caractères, une lettre (Unicode) et un chiffre', () => {
    expect(isValidPassword('abcdefg1')).toBe(true);
    expect(isValidPassword('ééééééé1')).toBe(true);
    expect(isValidPassword('abcdefgh')).toBe(false);
    expect(isValidPassword('12345678')).toBe(false);
    expect(isValidPassword('abc1')).toBe(false);
    expect(isValidPassword('a1'.repeat(65))).toBe(false);
  });
});
