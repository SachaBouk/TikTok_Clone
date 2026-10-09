import type {
  BlockRelations,
  Comment,
  CommentFilter,
  FollowDirection,
  FollowPosition,
  FollowRelations,
  ReactionPosition,
  VideoReaction,
  ViewerInteractions,
  ViewPosition,
} from './interaction';

// Port des tables likes, favorites, reposts, comments et follows (ADR-006).
// Ajouts et retraits idempotents : ajouter deux fois, ou retirer ce qui n'existe pas, est sans effet.
export abstract class InteractionRepository {
  abstract addReaction(kind: VideoReaction, userId: string, videoId: string): Promise<void>;
  abstract removeReaction(kind: VideoReaction, userId: string, videoId: string): Promise<void>;

  // Vidéos likées, mises en favori ou republiées par `userId`, de l'action la plus récente à la plus ancienne
  // (à date égale, par identifiant de vidéo décroissant), strictement après `after` s'il est donné.
  abstract listReactions(kind: VideoReaction, userId: string, after: ReactionPosition | null, limit: number): Promise<ReactionPosition[]>;

  // Historique de visionnage (table view_history, ADR-006) : une ligne par compte et par vidéo.
  // Crée la ligne, ou avance sa date au nouveau visionnage. Le trigger de la base n'incrémente views_count
  // qu'à la création : `views_count` compte les comptes distincts, et effacer l'historique ne le baisse pas.
  abstract recordView(userId: string, videoId: string): Promise<void>;
  // Du visionnage le plus récent au plus ancien (à date égale, par identifiant de vidéo décroissant),
  // strictement après `after` s'il est donné.
  abstract listViews(userId: string, after: ViewPosition | null, limit: number): Promise<ViewPosition[]>;
  abstract removeView(userId: string, videoId: string): Promise<void>;
  abstract clearViews(userId: string): Promise<void>;

  // Vrai si l'abonnement a réellement été ajouté ou retiré (compteurs changés).
  abstract follow(followerId: string, followingId: string): Promise<boolean>;
  abstract unfollow(followerId: string, followingId: string): Promise<boolean>;
  // Abonnés (`followers`) ou abonnements (`following`) de `userId`, du follow le plus récent au plus ancien
  // (à date égale, par identifiant décroissant), strictement après `after` s'il est donné.
  abstract listFollows(direction: FollowDirection, userId: string, after: FollowPosition | null, limit: number): Promise<FollowPosition[]>;
  // Tous les comptes que `userId` suit, dans un ordre quelconque (feed des abonnements).
  abstract listFollowingIds(userId: string): Promise<string[]>;
  // Tous les abonnés de `userId`, dans un ordre quelconque (live : abonnés prévenus, ADR-053).
  abstract listFollowerIds(userId: string): Promise<string[]>;
  // Parmi `otherIds`, ceux que `userId` suit et ceux qui le suivent.
  abstract findFollowRelations(userId: string, otherIds: string[]): Promise<FollowRelations>;

  abstract createComment(comment: { videoId: string; userId: string; content: string }): Promise<Comment>;
  abstract findComment(id: string): Promise<Comment | null>;
  // Commentaires existants parmi `ids`, dans un ordre quelconque.
  abstract findCommentsByIds(ids: string[]): Promise<Comment[]>;
  abstract deleteComment(id: string): Promise<void>;
  // Du plus récent au plus ancien, strictement avant `beforeId` s'il est donné (identifiants UUID v7, ordonnés).
  abstract listComments(videoId: string, beforeId: string | null, limit: number): Promise<Comment[]>;
  // Commentaires écrits par `userId`, même ordre et même curseur (historique du centre d'activités, ADR-006).
  abstract listUserComments(userId: string, beforeId: string | null, limit: number): Promise<Comment[]>;
  // Backoffice (ADR-004) : tous les commentaires, filtrés par vidéo et par auteur s'ils sont donnés, même ordre et même curseur.
  abstract findComments(filter: CommentFilter, beforeId: string | null, limit: number): Promise<Comment[]>;
  // Nombre de commentaires, écrits depuis `createdSince` s'il est donné.
  abstract countComments(createdSince: Date | null): Promise<number>;

  // Blocage : ajoute le blocage et supprime les follows dans les deux sens (les triggers ajustent les compteurs).
  // Vrai si un follow a été supprimé.
  abstract block(blockerId: string, blockedId: string): Promise<boolean>;
  abstract unblock(blockerId: string, blockedId: string): Promise<void>;
  // L'un des deux a-t-il bloqué l'autre ?
  abstract isBlockedBetween(userId: string, otherId: string): Promise<boolean>;
  abstract findBlocks(userId: string, otherIds: string[]): Promise<BlockRelations>;
  // Tous les comptes bloqués par `userId` ou qui l'ont bloqué (contenus à masquer au compte connecté).
  abstract findBlockedEitherWay(userId: string): Promise<Set<string>>;
  // Comptes bloqués par `blockerId`, du plus récent au plus ancien.
  abstract listBlocked(blockerId: string): Promise<string[]>;

  // Parmi `userIds`, ceux qui suivent `userId` et que `userId` suit.
  abstract findMutualFollows(userId: string, userIds: string[]): Promise<Set<string>>;

  abstract findViewerInteractions(userId: string, videoIds: string[], authorIds: string[]): Promise<ViewerInteractions>;
}
