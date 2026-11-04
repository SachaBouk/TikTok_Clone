import { sign, type KeyObject } from 'node:crypto';

// Jetons de lecture signée de Mux (ADR-074, vidéos privées) : JWT RS256, `sub` = identifiant de lecture, `aud` = usage
// (`v` : vidéo et fichiers statiques, `t` : miniature), `exp` en secondes, `kid` = identifiant de la clé de signature.

export type PlaybackAudience = 'v' | 't';

// Échéance arrondie à une fenêtre de 6 h, au moins 6 h devant soi : dans une même fenêtre le jeton est identique (RS256 est
// déterministe), donc l'URL aussi, et le cache des miniatures de l'app la reconnaît.
export const PLAYBACK_TOKEN_WINDOW_SECONDS = 6 * 3600;

export function playbackTokenExpiry(now: Date): number {
  const window = PLAYBACK_TOKEN_WINDOW_SECONDS;
  return (Math.floor(now.getTime() / 1000 / window) + 2) * window;
}

export function signPlaybackToken(playbackId: string, audience: PlaybackAudience, keyId: string, key: KeyObject, now: Date): string {
  const header = encode({ alg: 'RS256', typ: 'JWT', kid: keyId });
  const payload = encode({ sub: playbackId, aud: audience, exp: playbackTokenExpiry(now), kid: keyId });
  const signature = sign('RSA-SHA256', Buffer.from(`${header}.${payload}`), key).toString('base64url');
  return `${header}.${payload}.${signature}`;
}

function encode(value: object): string {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}
