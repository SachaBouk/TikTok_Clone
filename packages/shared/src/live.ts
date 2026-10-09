import type { UserSummaryDto } from './users.js';
import type { GiftDto } from './wallet.js';

// Live (ADR-053) : la vidéo passe par le serveur LiveKit ; l'API délivre les jetons d'accès, tient le chat, les cœurs et
// les cadeaux, et les diffuse dans la salle (messages de données de LiveKit).

export type LiveStatus = 'live' | 'ended';
// Fin : par l'auteur, à la durée maximale, auteur déconnecté, par un administrateur, à la suspension du compte.
export type LiveEndReason = 'host' | 'timeLimit' | 'disconnected' | 'moderation' | 'suspension';

export interface LiveDto {
  id: string;
  userId: string;
  title: string | null;
  status: LiveStatus;
  startedAt: string;
  endedAt: string | null;
  // Absente tant que le live est en cours.
  endReason?: LiveEndReason;
}

// Chiffres d'un live, pour son auteur seulement.
export interface LiveStatsDto {
  // Durée écoulée, ou totale une fois le live terminé.
  durationSeconds: number;
  // Plus grand nombre de spectateurs en même temps, et spectateurs distincts (invités compris).
  peakViewers: number;
  viewersCount: number;
  heartsCount: number;
  giftsCount: number;
  // Jetons reçus en cadeaux pendant le live.
  giftsAmount: number;
}

export interface LiveItemDto extends LiveDto {
  host: UserSummaryDto;
  // Pour l'auteur seulement.
  stats?: LiveStatsDto;
}

export interface LiveChatMessageDto {
  id: string;
  liveId: string;
  user: UserSummaryDto;
  content: string;
  createdAt: string;
}

// Accès à la salle du serveur vidéo : l'auteur publie sa caméra et son micro, un spectateur ne fait que regarder.
export type LiveRole = 'host' | 'viewer';

export interface LiveConnectionDto {
  live: LiveItemDto;
  role: LiveRole;
  // Serveur LiveKit (WebSocket) et jeton d'accès signé par l'API.
  url: string;
  token: string;
  // Derniers messages du chat, du plus ancien au plus récent.
  recentMessages: LiveChatMessageDto[];
}

export interface LiveHeartsDto {
  // Cœurs reçus par le live depuis son début.
  total: number;
}

// Live partagé dans un message (ADR-053) : `available` faux une fois terminé (ou masqué au lecteur).
export interface MessageLiveDto {
  id: string;
  available: boolean;
  // Présents tant que le live est visible du lecteur (en cours ou terminé).
  title?: string | null;
  host?: UserSummaryDto;
}

// Lives en cours des comptes suivis (rangée de la boîte de réception).
export interface FollowingLivesDto {
  items: LiveItemDto[];
}

// ─── Événements diffusés dans la salle (messages de données de LiveKit, sujet `live`) ───

export interface LiveChatMessageDeletedDto {
  messageId: string;
}

export interface LiveHeartsEventDto {
  // Cœurs de ce lot, et total du live.
  count: number;
  total: number;
}

export interface LiveGiftEventDto {
  sender: UserSummaryDto;
  gift: GiftDto;
  amount: number;
  // Totaux du live après ce cadeau.
  giftsCount: number;
  giftsAmount: number;
}

export interface LiveEndedEventDto {
  reason: LiveEndReason;
}

export type LiveRoomEvent =
  | { event: 'chatMessage'; data: LiveChatMessageDto }
  | { event: 'chatMessageDeleted'; data: LiveChatMessageDeletedDto }
  | { event: 'hearts'; data: LiveHeartsEventDto }
  | { event: 'gift'; data: LiveGiftEventDto }
  | { event: 'liveEnded'; data: LiveEndedEventDto };

// Sujet des messages de données de LiveKit qui portent ces événements.
export const LIVE_ROOM_TOPIC = 'live';
