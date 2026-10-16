import type { RateLimitRule } from '../../../rate-limit/rate-limiter';

// Interactions sociales (ADR-016). Les compteurs associés (likes_count, followers_count…) sont maintenus
// par des triggers PostgreSQL (migration interaction_counters) : ce module n'écrit que ses propres tables.

// Réactions à une vidéo, chacune dans sa table à clé composite (ADR-006) : impossibles en double.
export type VideoReaction = 'like' | 'favorite' | 'repost';

export interface Comment {
  id: string;
  videoId: string;
  userId: string;
  // Commentaire d'origine d'une réponse (ADR-060, un seul niveau) ; nul pour un commentaire.
  parentId: string | null;
  content: string;
  // Tenus par des triggers (migration comment_threads) ; comptent aussi les comptes masqués.
  repliesCount: number;
  likesCount: number;
  createdAt: Date;
}

// Filtres de la liste des commentaires du backoffice (ADR-004).
export interface CommentFilter {
  videoId?: string;
  userId?: string;
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

// Qui partage une vidéo (route publique) : le compte connecté, sinon l'adresse IP de l'invité.
export type Sharer = { userId: string } | { ip: string };

// Partages comptés (ADR-030) : au plus un par vidéo et par personne (compte ou IP) sur 24 h glissantes.
// Les suivants sont acceptés sans être comptés : le compteur ne se gonfle pas en rappelant la route.
export const SHARE_DEDUP_SECONDS = 24 * 3600;

// Limites de débit des actions (ADR-039), par compte, fenêtres fixes. Seuls les ajouts comptent : retirer un like
// ou se désabonner reste toujours possible ; ce sont les ajouts qui notifient (et envoient des push).
// Au-delà : 429 avec Retry-After. Une tentative refusée (par la limite ou un autre contrôle) n'est pas comptée.
// Like, favori et republication partagent la même limite.
export const REACTION_RATE_LIMITS: RateLimitRule[] = [
  { limit: 60, windowSeconds: 60 },
  { limit: 600, windowSeconds: 3600 },
];
export const COMMENT_RATE_LIMITS: RateLimitRule[] = [
  { limit: 10, windowSeconds: 60 },
  { limit: 100, windowSeconds: 3600 },
];
export const FOLLOW_RATE_LIMITS: RateLimitRule[] = [
  { limit: 30, windowSeconds: 60 },
  { limit: 200, windowSeconds: 24 * 3600 },
];
// Vues : envoyées seules par l'app après 1 s de lecture. Au-delà, la vue est ignorée sans erreur (204), comme un
// partage en double : ni comptée ni ajoutée à l'historique.
export const VIEW_RATE_LIMITS: RateLimitRule[] = [{ limit: 600, windowSeconds: 3600 }];

export const MAX_COMMENT_LENGTH = 500;
export const DEFAULT_COMMENTS_PAGE_SIZE = 20;
export const MAX_COMMENTS_PAGE_SIZE = 50;
export const DEFAULT_FOLLOWS_PAGE_SIZE = 20;
export const MAX_FOLLOWS_PAGE_SIZE = 50;
// Relations lues en une fois (une page du centre d'activité : 50 notifications au plus).
export const MAX_RELATIONSHIP_IDS = 50;

// Comptes suggérés (ADR-058) : amis d'amis. Candidats = comptes suivis par ceux que l'on suit, et ses abonnés que
// l'on ne suit pas ; jamais soi-même, un compte déjà suivi ni un compte masqué (bloqué, suspendu). Classement : ceux
// qui nous suivent d'abord, puis le nombre de comptes suivis qui les suivent, puis l'identifiant. Pas de pagination.
export const DEFAULT_SUGGESTIONS = 20;
export const MAX_SUGGESTIONS = 50;
// Comptes suivis qui suivent la suggestion, affichés (« Suivi(e) par … »).
export const SUGGESTION_FOLLOWERS_SHOWN = 3;

export interface SuggestionCandidate {
  userId: string;
  followsMe: boolean;
  // Comptes que l'on suit et qui suivent ce compte : les plus récemment abonnés d'abord (3 au plus), et leur nombre.
  followedByIds: string[];
  followedByCount: number;
}
