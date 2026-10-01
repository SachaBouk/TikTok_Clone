import type { Conversation, ConversationView, Message } from './messaging';

// Port des tables conversations, conversation_participants et messages (ADR-006).
export abstract class ConversationRepository {
  // Conversation à deux entre ces comptes : l'existante, sinon une nouvelle. Jamais deux pour la même paire,
  // même sous requêtes concurrentes.
  abstract findOrCreateDirect(userId: string, otherUserId: string): Promise<string>;
  abstract findConversation(conversationId: string): Promise<Conversation | null>;

  // Null si `userId` n'y participe pas, ou si l'autre participant n'existe plus.
  abstract findView(conversationId: string, userId: string): Promise<ConversationView | null>;
  // Boîte de réception de `userId` : conversations acceptées et demandes qu'il a envoyées, ayant un message
  // visible, de la plus récemment active à la plus ancienne ; strictement avant `beforeMessageId` s'il est donné.
  abstract listInbox(userId: string, beforeMessageId: string | null, limit: number): Promise<ConversationView[]>;
  // Demandes reçues en attente (ni acceptées ni refusées), même ordre et même curseur.
  abstract listRequests(userId: string, beforeMessageId: string | null, limit: number): Promise<ConversationView[]>;
  // Expéditeurs des demandes reçues en attente (badge, après filtrage des comptes bloqués).
  abstract listPendingRequestSenders(userId: string): Promise<string[]>;

  // Ajoute le message, le marque lu pour son expéditeur et, selon le cas, accepte la conversation
  // ou y ouvre une demande de l'expéditeur.
  abstract addMessage(message: {
    conversationId: string;
    senderId: string;
    content: string;
    sharedVideoId: string | null;
    accept: boolean;
    openRequest: boolean;
  }): Promise<Message>;
  abstract findMessage(messageId: string): Promise<Message | null>;
  // Messages existants parmi `ids`, dans un ordre quelconque.
  abstract findMessagesByIds(ids: string[]): Promise<Message[]>;
  abstract deleteMessage(messageId: string): Promise<void>;
  // Du plus récent au plus ancien, strictement avant `beforeId` et après `afterId` s'ils sont donnés.
  abstract listMessages(conversationId: string, beforeId: string | null, afterId: string | null, limit: number): Promise<Message[]>;

  // Avance le repère de lecture de `userId` jusqu'au dernier message d'identifiant ≤ `upToId`
  // (jusqu'au dernier message sans `upToId`). Jamais en arrière. Renvoie le nouveau repère, ou null s'il n'a pas bougé.
  abstract markRead(conversationId: string, userId: string, upToId: string | null): Promise<string | null>;
  // Supprime la conversation pour `userId` : ses messages actuels lui sont masqués (et lus).
  abstract clearFor(conversationId: string, userId: string): Promise<void>;
  abstract accept(conversationId: string): Promise<void>;
  abstract decline(conversationId: string): Promise<void>;
  // Conversations acceptées où `userId` a au moins un message non lu.
  abstract countUnreadConversations(userId: string): Promise<number>;
}
