import { describe, expect, it } from 'vitest';
import { parseLoginIdentifier } from './login-rules';

describe('identifiant de connexion (ADR-055)', () => {
  it('reconnaît un email, un pseudo, et ignore le « @ » initial d’un pseudo', () => {
    expect(parseLoginIdentifier(' Alice@Example.com ')).toEqual({ kind: 'email', value: 'alice@example.com' });
    expect(parseLoginIdentifier('Lea.Martin')).toEqual({ kind: 'username', value: 'lea.martin' });
    expect(parseLoginIdentifier('@lea.martin')).toEqual({ kind: 'username', value: 'lea.martin' });
  });
});
