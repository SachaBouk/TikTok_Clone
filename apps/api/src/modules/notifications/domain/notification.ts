import type { User } from '../../users/domain/user';
import type { PublishedVideo } from '../../videos/domain/video';

// Centre d'activité (ADR-016) : une notification par action d'un compte sur les vidéos ou le compte d'un autre.
// Créées par le module interactions via NotificationsService (ADR-003).

export type NotificationType = 'like' | 'comment' | 'follow' | 'repost';

// Action qui produit une notification pour `recipientId`.
export type ActivityEvent =
  | { type: 'like' | 'repost'; actorId: string; recipientId: string; videoId: string }
  | { type: 'comment'; actorId: string; recipientId: string; videoId: string; commentId: string; commentText: string }
  | { type: 'follow'; actorId: string; recipientId: string };

// Actions réversibles : leur notification disparaît quand elles sont annulées (unlike, unfollow…).
// Un commentaire supprimé emporte sa notification par cascade dans la base.
export type RetractableActivity = Extract<ActivityEvent, { type: 'like' | 'repost' | 'follow' }>;

export interface Notification {
  id: string;
  recipientId: string;
  actorId: string;
  type: NotificationType;
  // Renseignés selon le type : vidéo pour like, commentaire et republication ; commentaire pour comment.
  videoId: string | null;
  commentId: string | null;
  // Copie du commentaire : ce module ne lit pas la table des commentaires (ADR-003).
  commentText: string | null;
  readAt: Date | null;
  createdAt: Date;
}

// Notification prête à afficher : auteur de l'action et vidéo, lus via les modules users et videos.
export interface NotificationWithContext {
  notification: Notification;
  actor: User;
  // Null pour un follow.
  video: PublishedVideo | null;
}

export const DEFAULT_NOTIFICATIONS_PAGE_SIZE = 20;
export const MAX_NOTIFICATIONS_PAGE_SIZE = 50;
