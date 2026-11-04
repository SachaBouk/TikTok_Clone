import { generateKeyPairSync, verify } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { PLAYBACK_TOKEN_WINDOW_SECONDS, playbackTokenExpiry, signPlaybackToken } from './playback-token';

const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const decode = (part: string): Record<string, unknown> => JSON.parse(Buffer.from(part, 'base64url').toString()) as Record<string, unknown>;

describe('signPlaybackToken', () => {
  const now = new Date('2026-11-04T10:30:00Z');

  it('produit un JWT RS256 vérifiable : identifiant de lecture, usage, échéance, clé', () => {
    const token = signPlaybackToken('pb-1', 't', 'key-1', privateKey, now);
    const [header, payload, signature] = token.split('.');
    expect(decode(header)).toEqual({ alg: 'RS256', typ: 'JWT', kid: 'key-1' });
    expect(decode(payload)).toMatchObject({ sub: 'pb-1', aud: 't', kid: 'key-1', exp: playbackTokenExpiry(now) });
    expect(verify('RSA-SHA256', Buffer.from(`${header}.${payload}`), publicKey, Buffer.from(signature, 'base64url'))).toBe(true);
  });

  it('donne le même jeton dans une même fenêtre de 6 h, valable 6 à 12 h', () => {
    const later = new Date(now.getTime() + 60 * 60 * 1000);
    expect(signPlaybackToken('pb-1', 'v', 'key-1', privateKey, later)).toBe(signPlaybackToken('pb-1', 'v', 'key-1', privateKey, now));
    const remaining = playbackTokenExpiry(now) - now.getTime() / 1000;
    expect(remaining).toBeGreaterThanOrEqual(PLAYBACK_TOKEN_WINDOW_SECONDS);
    expect(remaining).toBeLessThanOrEqual(2 * PLAYBACK_TOKEN_WINDOW_SECONDS);
  });
});
