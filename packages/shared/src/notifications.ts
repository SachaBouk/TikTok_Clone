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

// Badge du centre d'activité.
export interface UnreadNotificationsDto {
  unreadCount: number;
}
