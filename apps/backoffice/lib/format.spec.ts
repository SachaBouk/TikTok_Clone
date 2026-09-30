import { describe, expect, it } from 'vitest';
import { clientAddress, formatDelay, withQuery } from './format';

describe('withQuery', () => {
  it('ne garde que les paramètres renseignés', () => {
    expect(withQuery('/videos', { status: 'failed', userId: null, cursor: '' })).toBe('/videos?status=failed');
    expect(withQuery('/videos', {})).toBe('/videos');
    expect(withQuery('/users', { q: '@léa b' })).toBe('/users?q=%40l%C3%A9a+b');
  });
});

describe('formatDelay', () => {
  it('en secondes sous une minute, sinon en minutes arrondies au-dessus', () => {
    expect(formatDelay(30)).toBe('30 s');
    expect(formatDelay(60)).toBe('1 min');
    expect(formatDelay(841)).toBe('15 min');
  });
});

describe('clientAddress', () => {
  it('garde la première adresse de X-Forwarded-For', () => {
    expect(clientAddress('203.0.113.7, 10.0.0.2')).toBe('203.0.113.7');
    expect(clientAddress(' ::1 ')).toBe('::1');
    expect(clientAddress(null)).toBeNull();
    expect(clientAddress('')).toBeNull();
  });
});
