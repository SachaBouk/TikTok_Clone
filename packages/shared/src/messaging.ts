import type { MessageLiveDto } from './live.js';
import type { MessageStoryDto } from './stories.js';
import type { UserSummaryDto } from './users.js';

// Messagerie directe (ADR-016) : conversations à deux et chats de groupe (ADR-059). Abonnés mutuels ou conversation
// acceptée : envoi libre ; sinon, demande de message (3 messages au plus avant acceptation). Messages texte et/ou vidéo
// partagée.

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
  // Live partagé (ADR-053).
  live?: MessageLiveDto;
  // Identifiant d'envoi choisi par l'app (ADR-044) : seulement dans la réponse à l'envoi et l'écho temps réel adressé à
  // l'expéditeur, pour reconnaître la bulle en attente.
  clientMessageId?: string;
  // Dans un groupe (ADR-059) : l'expéditeur, absent si son compte n'existe plus.
  sender?: UserSummaryDto;
  // Ligne d'événement d'un groupe ; absent pour un message.
  event?: GroupEventDto;
  createdAt: string;
}

// Ligne d'événement d'un groupe (ADR-059), faite par l'expéditeur du message.
export type GroupEventType = 'created' | 'added' | 'removed' | 'left' | 'renamed';

export interface GroupEventDto {
  type: GroupEventType;
  // Membre ajouté ou retiré ; absent pour les autres types, ou si son compte n'existe plus.
  user?: UserSummaryDto;
  // Nouveau nom d'un renommage (null : nom retiré) ; absent pour les autres types.
  name?: string | null;
}

export type ConversationKind = 'direct' | 'group';

export interface GroupMemberDto {
  user: UserSummaryDto;
  joinedAt: string;
  // Dernier message lu (« Vu par »).
  lastReadMessageId: string | null;
}

// Chat de groupe (ADR-059), vu par l'un de ses membres.
export interface GroupDto {
  // Null : l'app affiche les noms des membres.
  name: string | null;
  // Administrateur : le membre le plus ancien.
  adminId: string;
  // Groupe en sourdine pour le compte connecté (pas de notification push).
  muted: boolean;
  // Du plus ancien au plus récent, compte connecté compris.
  members: GroupMemberDto[];
}

// Pour le compte connecté : conversation libre, demande qu'il a envoyée, ou demande reçue (à accepter ou refuser).
export type ConversationStatus = 'direct' | 'requestSent' | 'requestReceived';

// Une conversation vue par le compte connecté.
export interface ConversationDto {
  id: string;
  kind: ConversationKind;
  // L'autre participant ; absent pour un groupe.
  participant?: UserSummaryDto;
  // Absent pour une conversation à deux.
  group?: GroupDto;
  // Toujours `direct` pour un groupe.
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

// Message trouvé par la recherche (ADR-058) : il ouvre sa conversation.
export interface MessageSearchResultDto {
  conversationId: string;
  messageId: string;
  content: string;
  createdAt: string;
  // L'autre participant de la conversation ; dans un groupe, l'expéditeur.
  participant: UserSummaryDto;
  sender: UserSummaryDto;
  // Message d'un groupe (ADR-059) ; absent sinon.
  group?: MessageSearchGroupDto;
}

export interface MessageSearchGroupDto {
  name: string | null;
  members: UserSummaryDto[];
}

export interface MessageSearchResultListDto {
  items: MessageSearchResultDto[];
}
