// Jeton de Participant du Live commun d'echimine (ADR-079). Le serveur commun `live.echimine.fr` ne connaît pas nos
// comptes : l'API signe pour le compte connecté un JWT HS256 (`iss` = notre App membre, `sub`, `name`, `picture`,
// `iat`, `exp` 5 min au plus), avec le secret transmis en privé par echimine. Aucun rôle : le serveur décide seul.

// Durée de vie du jeton : 5 min au plus, exigé par le serveur commun (le SDK en redemande un à chaque connexion).
export const PARTICIPANT_TOKEN_TTL_SECONDS = 5 * 60;

// Pseudo affiché dans le Live : 1 à 30 caractères visibles, sinon le jeton est refusé.
export const PARTICIPANT_NAME_MAX_LENGTH = 30;

export interface ParticipantClaims {
  sub: string;
  name: string;
  // Photo de profil, seulement en https (le serveur commun ignore le reste ; en local, MinIO sert en http).
  picture?: string;
}

// Compte vu par le Live commun : ce qu'il faut pour les claims, rien de plus.
export interface ParticipantAccount {
  id: string;
  username: string;
  avatarUrl: string | null;
}

// Port : comptes, lus par le module `users` (ADR-003).
export abstract class ParticipantAccounts {
  abstract find(userId: string): Promise<ParticipantAccount | null>;
}

// Port : signature du jeton. `available` faux sans secret configuré.
export abstract class ParticipantTokenSigner {
  abstract readonly available: boolean;
  abstract sign(claims: ParticipantClaims): Promise<string>;
}

export class CrossLiveError extends Error {}

// Secret de l'App membre absent (`LIVE_SDK_TOKEN_SECRET`) : le Live commun est indisponible.
export class CrossLiveUnavailableError extends CrossLiveError {
  constructor() {
    super('Le Live est indisponible pour le moment.');
  }
}

export class ParticipantNotFoundError extends CrossLiveError {
  constructor() {
    super('Compte introuvable.');
  }
}

const graphemes = new Intl.Segmenter(undefined, { granularity: 'grapheme' });

// Pseudo tronqué à 30 caractères visibles : un emoji composé n'est jamais coupé.
export function participantName(username: string): string {
  return Array.from(graphemes.segment(username.trim()), (segment) => segment.segment)
    .slice(0, PARTICIPANT_NAME_MAX_LENGTH)
    .join('');
}

export function participantClaims(account: ParticipantAccount): ParticipantClaims {
  const claims: ParticipantClaims = { sub: account.id, name: participantName(account.username) };
  if (account.avatarUrl?.startsWith('https://')) claims.picture = account.avatarUrl;
  return claims;
}
