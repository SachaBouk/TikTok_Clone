import type { RateLimitRule } from '../../../rate-limit/rate-limiter';

// Live (ADR-053) : un compte filme en direct depuis l'app ; la vidéo passe par le serveur LiveKit (une salle par live),
// jamais par l'API. Le live est gardé à sa fin pour ses chiffres (pas de replay) ; son chat est supprimé.

export type LiveStatus = 'live' | 'ended';
export type LiveEndReason = 'host' | 'timeLimit' | 'disconnected' | 'moderation' | 'suspension';

export const LIVE_STATUSES: LiveStatus[] = ['live', 'ended'];
export const LIVE_END_REASONS: LiveEndReason[] = ['host', 'timeLimit', 'disconnected', 'moderation', 'suspension'];

export interface Live {
  id: string;
  userId: string;
  title: string | null;
  status: LiveStatus;
  startedAt: Date;
  endedAt: Date | null;
  endReason: LiveEndReason | null;
  peakViewers: number;
  heartsCount: number;
  giftsCount: number;
  giftsAmount: number;
}

export interface LiveMessage {
  id: string;
  liveId: string;
  userId: string;
  content: string;
  createdAt: Date;
}

// Chiffres d'un live pour son auteur : ceux de la ligne, plus les spectateurs distincts (comptés à la lecture).
export interface LiveStats {
  durationSeconds: number;
  peakViewers: number;
  viewersCount: number;
  heartsCount: number;
  giftsCount: number;
  giftsAmount: number;
}

// Règles (ADR-053, choix du développeur).
export const LIVE_MAX_DURATION_MS = 2 * 3600 * 1000;
// Auteur déconnecté du serveur vidéo : le live s'arrête s'il n'est pas revenu dans ce délai.
export const HOST_RECONNECT_GRACE_MS = 60_000;
// Au lancement : délai laissé à l'app pour se connecter à la salle.
export const HOST_FIRST_CONNECT_GRACE_MS = 120_000;
export const MAX_LIVE_TITLE_LENGTH = 80;
export const MAX_LIVE_MESSAGE_LENGTH = 150;
export const RECENT_LIVE_MESSAGES = 50;
// Cœurs envoyés par lots : au plus ce nombre par requête.
export const MAX_HEARTS_PER_BATCH = 30;
// Lives en cours des comptes suivis (rangée) : au plus.
export const MAX_FOLLOWING_LIVES = 100;
// Jetons d'accès à la salle : valables le temps d'un live, plus une marge.
export const LIVE_TOKEN_TTL_SECONDS = 3 * 3600;
// Maintenance : lives en cours relus par passe.
export const LIVE_MAINTENANCE_BATCH_SIZE = 200;

// Limites de débit (ADR-039) : lancements par compte, messages du chat, envois de cœurs (requêtes).
export const LIVE_START_RATE_LIMITS: RateLimitRule[] = [{ limit: 10, windowSeconds: 24 * 3600 }];
export const LIVE_MESSAGE_RATE_LIMITS: RateLimitRule[] = [
  { limit: 20, windowSeconds: 60 },
  { limit: 300, windowSeconds: 3600 },
];
export const LIVE_HEARTS_RATE_LIMITS: RateLimitRule[] = [{ limit: 120, windowSeconds: 60 }];

// Identité dans la salle : un compte (`user:<id>`), ou un invité (`guest:<id>`, tiré au hasard à chaque arrivée).
export function userIdentity(userId: string): string {
  return `user:${userId}`;
}

export function guestIdentity(id: string): string {
  return `guest:${id}`;
}

// Compte d'une identité de la salle ; null pour un invité ou une identité inconnue.
export function userIdOfIdentity(identity: string): string | null {
  return identity.startsWith('user:') ? identity.slice('user:'.length) : null;
}

// Titre nettoyé ; null s'il est vide.
export function sanitizeTitle(title: string | null | undefined): string | null {
  const trimmed = title?.trim() ?? '';
  return trimmed === '' ? null : trimmed;
}

export function isInProgress(live: Live): boolean {
  return live.status === 'live';
}

export function durationSeconds(live: Live, now: Date): number {
  const end = live.endedAt ?? now;
  return Math.max(0, Math.floor((end.getTime() - live.startedAt.getTime()) / 1000));
}

export function timeLimitOf(live: Live): Date {
  return new Date(live.startedAt.getTime() + LIVE_MAX_DURATION_MS);
}
