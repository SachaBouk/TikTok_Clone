import type { Live, LiveEndReason, LiveMessage } from './live';

export interface NewLive {
  id: string;
  userId: string;
  title: string | null;
  startedAt: Date;
}

export interface NewLiveMessage {
  liveId: string;
  userId: string;
  content: string;
  createdAt: Date;
}

// Port des lives (ADR-053).
export abstract class LiveRepository {
  // null si le compte a déjà un live en cours (index unique partiel).
  abstract create(live: NewLive): Promise<Live | null>;
  abstract findById(id: string): Promise<Live | null>;
  abstract findByIds(ids: string[]): Promise<Live[]>;
  abstract findInProgressByUser(userId: string): Promise<Live | null>;
  // Lives en cours de ces comptes, du plus récent au plus ancien.
  abstract findInProgressByUsers(userIds: string[]): Promise<Live[]>;
  // Termine le live s'il est en cours (atomique) ; null s'il était déjà terminé.
  abstract end(id: string, reason: LiveEndReason, at: Date): Promise<Live | null>;

  // Spectateur arrivé (une ligne par identité) ; pic de spectateurs relevé.
  abstract recordViewer(liveId: string, identity: string, at: Date): Promise<void>;
  abstract raisePeakViewers(liveId: string, count: number): Promise<void>;
  // Spectateurs distincts, sans l'auteur.
  abstract countViewers(liveId: string, excludedIdentity: string): Promise<number>;
  // Cœurs ajoutés ; renvoie le total du live.
  abstract addHearts(liveId: string, count: number): Promise<number>;
  // Cadeau compté ; renvoie les totaux du live.
  abstract addGift(liveId: string, amount: number): Promise<{ giftsCount: number; giftsAmount: number }>;

  // Chat.
  abstract addMessage(message: NewLiveMessage): Promise<LiveMessage>;
  abstract findMessage(id: string): Promise<LiveMessage | null>;
  abstract deleteMessage(id: string): Promise<void>;
  // Derniers messages, du plus ancien au plus récent, sans ceux des comptes `excludedUserIds`.
  abstract listRecentMessages(liveId: string, limit: number, excludedUserIds: string[]): Promise<LiveMessage[]>;
  abstract deleteMessages(liveId: string): Promise<void>;

  // Maintenance : lives en cours (les plus anciens d'abord).
  abstract findInProgress(limit: number): Promise<Live[]>;
}
