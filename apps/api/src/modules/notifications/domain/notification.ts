import type { User } from '../../users/domain/user';
import type { PublishedVideo } from '../../videos/domain/video';

// Centre d'activité (ADR-016) : une notification par action d'un compte sur les vidéos ou le compte d'un autre.
// Créées par le module interactions via NotificationsService (ADR-003).

// `reportResolved` et `contentRemoved` : modération (ADR-038), sans auteur.
export type NotificationType = 'like' | 'comment' | 'follow' | 'repost' | 'reportResolved' | 'contentRemoved';

// Modération (ADR-038). Mêmes valeurs que le module reports, recopiées : ce module n'en dépend pas (c'est reports
// qui le prévient).
export type ModerationTargetType = 'video' | 'comment' | 'account' | 'message';
export type ModerationReason = 'spam' | 'harassment' | 'hate' | 'violence' | 'sexual' | 'impersonation' | 'other';
// Décision sur un signalement, annoncée à la personne qui l'a envoyé.
export type ModerationOutcome = 'contentRemoved' | 'accountSuspended' | 'dismissed';

export interface ModerationDetails {
  targetType: ModerationTargetType;
  // Contenu retiré : motif choisi par l'administrateur.
  reason: ModerationReason | null;
  // Signalement examiné : décision.
  outcome: ModerationOutcome | null;
  // Texte du contenu concerné, copié.
  excerpt: string | null;
}

// Notification de modération, sans auteur : à la personne qui a signalé (décision), ou à l'auteur d'un contenu retiré.
export type ModerationEvent =
  | { type: 'reportResolved'; recipientId: string; targetType: ModerationTargetType; outcome: ModerationOutcome; excerpt: string | null }
  | { type: 'contentRemoved'; recipientId: string; targetType: ModerationTargetType; reason: ModerationReason; excerpt: string | null };

export const MODERATION_TYPES: NotificationType[] = ['reportResolved', 'contentRemoved'];
// Listes complètes, pour la spec OpenAPI (mêmes enums nommés que le module reports).
export const NOTIFICATION_TYPES: NotificationType[] = ['like', 'comment', 'follow', 'repost', 'reportResolved', 'contentRemoved'];
export const MODERATION_TARGET_TYPES: ModerationTargetType[] = ['video', 'comment', 'account', 'message'];
export const MODERATION_REASONS: ModerationReason[] = ['spam', 'harassment', 'hate', 'violence', 'sexual', 'impersonation', 'other'];
export const MODERATION_OUTCOMES: ModerationOutcome[] = ['contentRemoved', 'accountSuspended', 'dismissed'];

export function isModeration(type: NotificationType): boolean {
  return MODERATION_TYPES.includes(type);
}

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
  // Nul pour une notification de modération.
  actorId: string | null;
  type: NotificationType;
  // Renseignés selon le type : vidéo pour like, commentaire et republication ; commentaire pour comment.
  videoId: string | null;
  commentId: string | null;
  // Copie du commentaire : ce module ne lit pas la table des commentaires (ADR-003).
  commentText: string | null;
  // Notifications de modération seulement.
  moderation: ModerationDetails | null;
  readAt: Date | null;
  createdAt: Date;
}

// Notification prête à afficher : auteur de l'action et vidéo, lus via les modules users et videos.
export interface NotificationWithContext {
  notification: Notification;
  // Nul pour une notification de modération.
  actor: User | null;
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
    // Modération : chaque notification seule.
    case 'reportResolved':
    case 'contentRemoved':
      return `moderation:${notification.id}`;
  }
}

// Notifications d'un groupe, pour sa liste complète : `type`, et la vidéo pour un like ou une republication.
export interface NotificationFilter {
  type?: NotificationType;
  videoId?: string;
}

export const DEFAULT_NOTIFICATIONS_PAGE_SIZE = 20;
export const MAX_NOTIFICATIONS_PAGE_SIZE = 50;
