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

// Regroupement à la lecture (choix du développeur, comme TikTok) : like et republication par vidéo,
// tous les follows ensemble, chaque commentaire seul (son texte compte). Le stockage ne change pas.
export interface NotificationGroup {
  // Notification la plus récente du groupe : type, vidéo, commentaire ; son identifiant sert de curseur.
  latest: Notification;
  count: number;
  unread: boolean;
  // Auteurs des notifications les plus récentes, du plus récent au plus ancien.
  recentActorIds: string[];
}

export interface NotificationGroupWithContext {
  group: NotificationGroup;
  actors: User[];
  video: PublishedVideo | null;
}

// Nombre d'auteurs affichés par groupe (« Inès, Nathan et 3 autres »).
export const GROUP_ACTORS_SHOWN = 2;

export function groupKey(notification: Notification): string {
  switch (notification.type) {
    case 'like':
    case 'repost':
      return `${notification.type}:${notification.videoId}`;
    case 'follow':
      return 'follow';
    case 'comment':
      return `comment:${notification.id}`;
  }
}

// Notifications d'un groupe, pour sa liste complète : `type`, et la vidéo pour un like ou une republication.
export interface NotificationFilter {
  type?: NotificationType;
  videoId?: string;
}

export const DEFAULT_NOTIFICATIONS_PAGE_SIZE = 20;
export const MAX_NOTIFICATIONS_PAGE_SIZE = 50;
