import { describe, expect, it } from 'vitest';
import { parseTrustProxy } from './trust-proxy';

describe('parseTrustProxy', () => {
  it('pas de proxy par défaut', () => {
    expect(parseTrustProxy(undefined)).toBe(false);
    expect(parseTrustProxy('  ')).toBe(false);
    expect(parseTrustProxy('false')).toBe(false);
  });

  it('nombre de proxys, tous, ou liste d’adresses', () => {
    expect(parseTrustProxy('1')).toBe(1);
    expect(parseTrustProxy('true')).toBe(true);
    expect(parseTrustProxy(' loopback, 10.0.0.0/8 ')).toBe('loopback, 10.0.0.0/8');
  });
});
