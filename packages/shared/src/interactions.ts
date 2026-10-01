import type { UserSummaryDto } from './users.js';

// Interactions sociales (ADR-016) : like, favori, republication, partage, commentaire, follow.

// État après un like, un favori, une republication ou un follow (idempotents : PUT active, DELETE désactive).
export interface InteractionStateDto {
  // L'utilisateur connecté a-t-il désormais liké / mis en favori / republié / suivi ?
  active: boolean;
  // Compteur à jour : likes, favoris ou republications de la vidéo, abonnés du compte.
  count: number;
}

export interface ShareResultDto {
  sharesCount: number;
}

export interface CommentDto {
  id: string;
  videoId: string;
  content: string;
  createdAt: string;
  author: UserSummaryDto;
}

// Comptes bloqués par le compte connecté (réglages de l'app), du plus récent au plus ancien.
export interface BlockedUsersDto {
  items: UserSummaryDto[];
}

export interface CommentPageDto {
  // Du plus récent au plus ancien.
  items: CommentDto[];
  // À renvoyer tel quel pour la page suivante ; null s'il n'y a plus de commentaires.
  nextCursor: string | null;
}

// Listes d'abonnés et d'abonnements d'un compte (publiques, lisibles en mode invité).

// Relation entre le compte connecté et un compte de la liste (bouton « Suivre », « Suivre en retour », « Ami(e)s »).
export interface FollowViewerStateDto {
  // Le compte connecté suit ce compte.
  following: boolean;
  // Ce compte suit le compte connecté.
  followedBy: boolean;
}

export interface FollowItemDto {
  user: UserSummaryDto;
  // Date du follow.
  followedAt: string;
  // Absent en mode invité (plutôt que null, comme `viewer` du feed).
  viewer?: FollowViewerStateDto;
}

export interface FollowPageDto {
  // Du follow le plus récent au plus ancien.
  items: FollowItemDto[];
  // À renvoyer tel quel pour la page suivante ; null s'il n'y en a plus.
  nextCursor: string | null;
}

// Relation entre le compte connecté et un autre compte (boutons de l'écran de profil).
export interface UserRelationshipDto {
  // Le compte connecté suit ce compte.
  following: boolean;
  // Ce compte suit le compte connecté.
  followedBy: boolean;
  // Le compte connecté a bloqué ce compte (« Débloquer »).
  blockedByMe: boolean;
}

// Relations du compte connecté avec plusieurs comptes (centre d'activité : « Suivre en retour »).
export interface UserRelationshipEntryDto extends UserRelationshipDto {
  userId: string;
}

export interface UserRelationshipListDto {
  // Dans l'ordre demandé, sans doublon.
  items: UserRelationshipEntryDto[];
}

// Historique des commentaires du compte connecté (centre d'activités, ADR-016). Privé.

// Vidéo commentée : miniature et auteur, pour la liste (comme la vidéo d'une notification).
export interface CommentedVideoDto {
  id: string;
  thumbnailUrl: string;
  author: UserSummaryDto;
}

export interface CommentHistoryItemDto {
  // Identifiant du commentaire (à passer à `DELETE /comments/:id` pour le supprimer).
  id: string;
  content: string;
  createdAt: string;
  video: CommentedVideoDto;
}

export interface CommentHistoryPageDto {
  // Du plus récent au plus ancien.
  items: CommentHistoryItemDto[];
  // À renvoyer tel quel pour la page suivante ; null s'il n'y en a plus.
  nextCursor: string | null;
}
