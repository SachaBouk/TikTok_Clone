import type { MessageStoryDto } from './stories.js';
import type { UserSummaryDto } from './users.js';

// Messagerie directe (ADR-016) : conversations à deux. Abonnés mutuels ou conversation acceptée : envoi libre ;
// sinon, demande de message (3 messages au plus avant acceptation). Messages texte et/ou vidéo partagée.

// Vidéo partagée dans un message. `available` faux si elle a été supprimée depuis : les autres champs sont alors nuls.
export interface SharedVideoDto {
  id: string;
  available: boolean;
  thumbnailUrl: string | null;
  hlsUrl: string | null;
  description: string | null;
  // Absent si la vidéo n'est plus disponible.
  author?: UserSummaryDto;
}

export interface MessageDto {
  id: string;
  conversationId: string;
  senderId: string;
  // Vide si le message ne fait que partager une vidéo.
  content: string;
  // Absent si le message ne partage pas de vidéo.
  sharedVideo?: SharedVideoDto;
  // Story à laquelle répond le message (ADR-051) ; absent sinon.
  story?: MessageStoryDto;
  // Identifiant d'envoi choisi par l'app (ADR-044) : seulement dans la réponse à l'envoi et l'écho temps réel adressé à
  // l'expéditeur, pour reconnaître la bulle en attente.
  clientMessageId?: string;
  createdAt: string;
}

// Pour le compte connecté : conversation libre, demande qu'il a envoyée, ou demande reçue (à accepter ou refuser).
export type ConversationStatus = 'direct' | 'requestSent' | 'requestReceived';

// Une conversation vue par le compte connecté.
export interface ConversationDto {
  id: string;
  // L'autre participant.
  participant: UserSummaryDto;
  status: ConversationStatus;
  // Absent pour une conversation vide (ou supprimée pour soi depuis son dernier message).
  lastMessage?: MessageDto;
  // Messages de l'autre participant non lus.
  unreadCount: number;
  // Dernier message lu par l'autre participant : « Vu » sous ses propres messages jusqu'à celui-ci.
  // Toujours null tant que la conversation n'est pas acceptée.
  participantLastReadMessageId: string | null;
  // Envoi possible : faux si l'un des deux a bloqué l'autre, ou si une demande envoyée a atteint sa limite.
  canSend: boolean;
  // Messages encore possibles dans une demande envoyée ; null hors demande envoyée.
  remainingRequestMessages: number | null;
  blockedByMe: boolean;
  createdAt: string;
}

export interface ConversationPageDto {
  // De la plus récemment active à la plus ancienne. Les conversations vides n'y figurent pas.
  items: ConversationDto[];
  // À renvoyer tel quel pour la page suivante ; null s'il n'y en a plus.
  nextCursor: string | null;
}

export interface MessagePageDto {
  // Du plus récent au plus ancien.
  items: MessageDto[];
  // À renvoyer tel quel pour la page suivante (messages plus anciens) ; null s'il n'y en a plus.
  nextCursor: string | null;
}

// Badges de la messagerie.
export interface UnreadConversationsDto {
  // Conversations (hors demandes) ayant au moins un message non lu.
  unreadCount: number;
  // Demandes reçues en attente.
  requestCount: number;
}
