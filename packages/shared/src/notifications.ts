import type { UserSummaryDto } from './users.js';

// Centre d'activité (ADR-016) : ce que les autres comptes ont fait sur mes vidéos et mon compte.

export type NotificationType = 'like' | 'comment' | 'follow' | 'repost';

// Vidéo concernée (like, commentaire, republication), pour afficher sa miniature.
export interface NotificationVideoDto {
  id: string;
  thumbnailUrl: string;
}

export interface NotificationCommentDto {
  id: string;
  content: string;
}

export interface NotificationDto {
  id: string;
  // `kind` plutôt que `type` : le générateur Swift renommerait `type` en `_type`.
  kind: NotificationType;
  // Auteur de l'action.
  actor: UserSummaryDto;
  // Absent pour un follow (plutôt que null : voir FeedItemDto.viewer).
  video?: NotificationVideoDto;
  // Présent pour un commentaire seulement.
  comment?: NotificationCommentDto;
  read: boolean;
  createdAt: string;
}

export interface NotificationPageDto {
  // Du plus récent au plus ancien.
  items: NotificationDto[];
  // À renvoyer tel quel pour la page suivante ; null s'il n'y en a plus.
  nextCursor: string | null;
}

// Groupe du centre d'activité, calculé à la lecture (« Inès, Nathan et 3 autres ont aimé ta vidéo ») :
// like et republication par vidéo, tous les follows ensemble, chaque commentaire seul.
export interface NotificationGroupDto {
  // Identifiant stable du groupe : `like:<videoId>`, `repost:<videoId>`, `follow`, `comment:<notificationId>`.
  key: string;
  kind: NotificationType;
  // Auteurs des notifications les plus récentes du groupe, 2 au plus, du plus récent au plus ancien.
  actors: UserSummaryDto[];
  // Nombre de notifications du groupe (une par compte pour un like, une republication ou un follow).
  count: number;
  // Like, republication, commentaire.
  video?: NotificationVideoDto;
  // Groupe d'un commentaire (toujours seul).
  comment?: NotificationCommentDto;
  // Faux si au moins une notification du groupe n'est pas lue.
  read: boolean;
  // Notification la plus récente du groupe : curseur de pagination, marquage lu.
  latestId: string;
  createdAt: string;
}

export interface NotificationGroupPageDto {
  // Du groupe le plus récemment actif au plus ancien.
  items: NotificationGroupDto[];
  // À renvoyer tel quel pour la page suivante ; null s'il n'y en a plus.
  nextCursor: string | null;
}

// Badge du centre d'activité.
export interface UnreadNotificationsDto {
  unreadCount: number;
}
