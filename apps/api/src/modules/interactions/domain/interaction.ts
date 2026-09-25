// Interactions sociales (ADR-016). Les compteurs associés (likes_count, followers_count…) sont maintenus
// par des triggers PostgreSQL (migration interaction_counters) : ce module n'écrit que ses propres tables.

// Réactions à une vidéo, chacune dans sa table à clé composite (ADR-006) : impossibles en double.
export type VideoReaction = 'like' | 'favorite' | 'repost';

export interface Comment {
  id: string;
  videoId: string;
  userId: string;
  content: string;
  createdAt: Date;
}

// Ce que l'utilisateur connecté a fait sur un ensemble de vidéos et d'auteurs (état des boutons du feed).
export interface ViewerInteractions {
  likedVideoIds: Set<string>;
  favoritedVideoIds: Set<string>;
  repostedVideoIds: Set<string>;
  followedUserIds: Set<string>;
}

// Blocages entre un compte et d'autres (pour la messagerie, qui ne lit pas la table blocks).
export interface BlockRelations {
  // Comptes que ce compte a bloqués.
  blockedByMe: Set<string>;
  // Comptes qui ont bloqué ce compte.
  blockedMe: Set<string>;
}

// Une vidéo mise en favori ou republiée, et la date de l'action. Sert aussi de position de pagination.
export interface ReactionPosition {
  videoId: string;
  reactedAt: Date;
}

// Une vidéo de l'historique de visionnage et la date du dernier visionnage. Sert aussi de position de pagination.
export interface ViewPosition {
  videoId: string;
  viewedAt: Date;
}

// Relation entre le compte connecté et un autre compte (écran de profil).
export interface Relationship {
  following: boolean;
  followedBy: boolean;
  blockedByMe: boolean;
}

// Sens d'une liste de follows : les abonnés d'un compte, ou ses abonnements.
export type FollowDirection = 'followers' | 'following';

// Un compte d'une liste d'abonnés ou d'abonnements, et la date du follow. Sert aussi de position de pagination.
export interface FollowPosition {
  userId: string;
  followedAt: Date;
}

// Relation entre un compte et d'autres (boutons des listes d'abonnés et d'abonnements).
export interface FollowRelations {
  // Comptes que ce compte suit.
  following: Set<string>;
  // Comptes qui suivent ce compte.
  followedBy: Set<string>;
}

export const MAX_COMMENT_LENGTH = 500;
export const DEFAULT_COMMENTS_PAGE_SIZE = 20;
export const MAX_COMMENTS_PAGE_SIZE = 50;
export const DEFAULT_FOLLOWS_PAGE_SIZE = 20;
export const MAX_FOLLOWS_PAGE_SIZE = 50;
