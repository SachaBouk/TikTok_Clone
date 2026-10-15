import type { RateLimitRule } from '../../../rate-limit/rate-limiter';
import type { User } from '../../users/domain/user';
import type { LiveItem } from '../../live/application/live.service';
import type { ActiveStory } from '../../stories/domain/story';
import type { PublishedVideo } from '../../videos/domain/video';

// Messagerie directe (ADR-016) : conversations à deux et chats de groupe (ADR-059), messages texte ou partage de
// vidéo, poussés par WebSocket (ADR-011) et notifications push.
// - Abonnés mutuels, ou conversation acceptée : on s'écrit librement.
// - Sinon, le premier message ouvre une demande : REQUEST_MESSAGE_LIMIT messages au plus tant que le
//   destinataire ne l'a pas acceptée (ou n'a pas répondu). Pas de « Vu » ni de « en train d'écrire » d'ici là.
// - Blocage (module interactions) : plus aucun envoi, dans les deux sens.

export interface Message {
  id: string;
  conversationId: string;
  senderId: string;
  // Vide si le message ne fait que partager une vidéo.
  content: string;
  sharedVideoId: string | null;
  // Story à laquelle répond le message (ADR-051) : un texte l'accompagne toujours.
  storyId: string | null;
  // Live partagé (ADR-053).
  liveId: string | null;
  // Ligne d'événement d'un groupe (ADR-059) : l'expéditeur en est l'auteur ; `content` = nouveau nom d'un renommage.
  event: GroupEvent | null;
  // Membre ajouté ou retiré.
  eventUserId: string | null;
  createdAt: Date;
}

export type ConversationKind = 'direct' | 'group';
export type GroupEvent = 'created' | 'added' | 'removed' | 'left' | 'renamed';

// Vidéo partagée, résolue à la lecture : null si elle a été supprimée depuis (message « indisponible »).
export interface SharedVideo {
  id: string;
  video: PublishedVideo | null;
  author: User | null;
}

// Story à laquelle répond un message, résolue à la lecture : null si elle a expiré, a été supprimée, ou si son auteur est
// masqué au lecteur (« Story expirée »).
export interface RepliedStory {
  id: string;
  story: ActiveStory | null;
}

// Live partagé, résolu à la lecture : null s'il est masqué au lecteur (blocage, auteur suspendu) ou si son compte a été
// supprimé ; sinon en cours ou terminé.
export interface SharedLive {
  id: string;
  item: LiveItem | null;
}

export interface MessageItem {
  message: Message;
  sharedVideo: SharedVideo | null;
  repliedStory: RepliedStory | null;
  sharedLive: SharedLive | null;
  // Identifiant d'envoi choisi par l'app (ADR-044), rendu à son seul expéditeur dans la réponse à l'envoi et l'écho temps
  // réel : l'app y reconnaît la bulle en attente. Absent ailleurs.
  clientMessageId?: string;
  // Dans un groupe (ADR-059) : l'expéditeur (absent si son compte n'existe plus) et le membre visé par un événement.
  sender?: User | null;
  eventUser?: User | null;
}

export interface ConversationMember {
  userId: string;
  // Repère de lecture : les messages d'identifiant supérieur (UUID v7, ordonnés) ne sont pas lus.
  lastReadMessageId: string | null;
  // Conversation supprimée pour ce participant jusqu'à ce message (repère, même principe).
  clearedUpToMessageId: string | null;
  // Entrée dans la conversation : l'administrateur d'un groupe est le membre le plus ancien (ADR-059).
  joinedAt: Date;
  // Groupe en sourdine pour ce membre : pas de notification push.
  mutedAt: Date | null;
}

export interface Conversation {
  id: string;
  createdAt: Date;
  kind: ConversationKind;
  // Nom d'un groupe ; toujours null pour une conversation à deux.
  name: string | null;
  requestSenderId: string | null;
  acceptedAt: Date | null;
  declinedAt: Date | null;
  members: ConversationMember[];
}

// Une conversation vue par l'un de ses participants (messages supprimés pour lui exclus).
export interface ConversationView {
  id: string;
  createdAt: Date;
  kind: ConversationKind;
  name: string | null;
  requestSenderId: string | null;
  accepted: boolean;
  declined: boolean;
  // L'autre participant ; null pour un groupe (membres lus à part).
  participantId: string | null;
  // Dernier message visible (dans un groupe : sans ceux des comptes masqués au lecteur).
  lastMessage: Message | null;
  // Messages des autres participants non lus par ce participant (ni lignes d'événement, ni messages masqués).
  unreadCount: number;
  // Dernier message lu par l'autre participant (« Vu ») ; null pour un groupe.
  participantLastReadMessageId: string | null;
  // Messages envoyés par ce participant (compté seulement tant que la conversation n'est pas acceptée).
  ownMessageCount: number;
}

// Pour le participant qui regarde : conversation libre, demande qu'il a envoyée, ou demande reçue.
export type ConversationStatus = 'direct' | 'requestSent' | 'requestReceived';

// Badges de la messagerie, envoyés avec chaque événement.
export interface MessagingBadges {
  // Conversations (hors demandes) ayant au moins un message non lu.
  unreadConversations: number;
  // Demandes reçues en attente.
  pendingRequests: number;
}

// Administrateur d'un groupe : le membre le plus ancien (ADR-059), départagé par l'identifiant.
export function groupAdminId(members: ConversationMember[]): string | null {
  const [admin] = [...members].sort((a, b) => a.joinedAt.getTime() - b.joinedAt.getTime() || (a.userId < b.userId ? -1 : 1));
  return admin?.userId ?? null;
}

// Chats de groupe (ADR-059) : 32 membres au plus, créateur compris ; au moins 2 amis à la création ; nom de 50 caractères.
export const MAX_GROUP_MEMBERS = 32;
export const MIN_GROUP_FRIENDS = 2;
export const MAX_GROUP_NAME_LENGTH = 50;
export const GROUP_CREATE_RATE_LIMITS: RateLimitRule[] = [{ limit: 20, windowSeconds: 24 * 3600 }];

export const MAX_MESSAGE_LENGTH = 1000;
export const DEFAULT_PAGE_SIZE = 20;
export const MAX_PAGE_SIZE = 50;
// Messages qu'on peut envoyer dans une demande pas encore acceptée.
export const REQUEST_MESSAGE_LIMIT = 3;
// Recherche dans les messages (ADR-058) : texte cherché et nombre de résultats.
export const MAX_SEARCH_QUERY_LENGTH = 100;
export const DEFAULT_SEARCH_RESULTS = 20;
export const MAX_SEARCH_RESULTS = 50;
// Limites d'envoi par compte (fenêtres fixes) : messages de toute sorte, et nouvelles demandes.
export const MESSAGE_RATE_LIMITS: RateLimitRule[] = [
  { limit: 20, windowSeconds: 60 },
  { limit: 300, windowSeconds: 3600 },
];
export const REQUEST_RATE_LIMITS: RateLimitRule[] = [{ limit: 10, windowSeconds: 24 * 3600 }];
// « En train d'écrire » : l'app renvoie l'indicateur toutes les ~3 s en tapant ; le serveur n'en relaie
// qu'un par intervalle, et l'app l'efface après TYPING_DISPLAY_SECONDS sans nouvel indicateur.
export const TYPING_THROTTLE_MS = 2000;
export const TYPING_DISPLAY_SECONDS = 5;
