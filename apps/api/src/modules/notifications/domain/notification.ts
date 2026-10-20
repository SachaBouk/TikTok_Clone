import type { User } from '../../users/domain/user';
import type { PublishedVideo } from '../../videos/domain/video';

// Centre d'activité (ADR-016) : une notification par action d'un compte sur les vidéos ou le compte d'un autre.
// Créées par le module interactions via NotificationsService (ADR-003).

// `reportResolved` et `contentRemoved` : modération (ADR-038), sans auteur. `gift` : cadeau reçu sur une vidéo (ADR-050).
// `live` : un compte suivi lance un live (ADR-053). `commentReply`, `commentLike`, `mention` : commentaires (ADR-060).
// `videoMention` : mention dans la description d'une vidéo publiée (ADR-065).
export type NotificationType =
  | 'like'
  | 'comment'
  | 'follow'
  | 'repost'
  | 'reportResolved'
  | 'contentRemoved'
  | 'gift'
  | 'live'
  | 'commentReply'
  | 'commentLike'
  | 'mention'
  | 'videoMention';

// Modération (ADR-038). Mêmes valeurs que le module reports, recopiées : ce module n'en dépend pas (c'est reports
// qui le prévient).
export type ModerationTargetType = 'video' | 'comment' | 'account' | 'message' | 'story' | 'live';
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
export const NOTIFICATION_TYPES: NotificationType[] = [
  'like',
  'comment',
  'follow',
  'repost',
  'reportResolved',
  'contentRemoved',
  'gift',
  'live',
  'commentReply',
  'commentLike',
  'mention',
  'videoMention',
];
export const MODERATION_TARGET_TYPES: ModerationTargetType[] = ['video', 'comment', 'account', 'message', 'story', 'live'];
export const MODERATION_REASONS: ModerationReason[] = ['spam', 'harassment', 'hate', 'violence', 'sexual', 'impersonation', 'other'];
export const MODERATION_OUTCOMES: ModerationOutcome[] = ['contentRemoved', 'accountSuspended', 'dismissed'];

export function isModeration(type: NotificationType): boolean {
  return MODERATION_TYPES.includes(type);
}

// Action qui produit une notification pour `recipientId`.
export type ActivityEvent =
  | { type: 'like' | 'repost'; actorId: string; recipientId: string; videoId: string }
  // Mention dans la description d'une vidéo publiée (ADR-065) : une par vidéo et par compte.
  | { type: 'videoMention'; actorId: string; recipientId: string; videoId: string }
  // Commentaire sur sa vidéo ; réponse à son commentaire (`commentId` : la réponse) ; mention dans un commentaire (ADR-060).
  | { type: 'comment' | 'commentReply' | 'mention'; actorId: string; recipientId: string; videoId: string; commentId: string; commentText: string }
  // J'aime sur son commentaire (ADR-060) : texte du commentaire aimé copié. Au plus une par compte et par commentaire.
  | { type: 'commentLike'; actorId: string; recipientId: string; videoId: string; commentId: string; commentText: string }
  | { type: 'follow'; actorId: string; recipientId: string }
  // Cadeau (ADR-050, module wallet) : code du catalogue et prix copiés (ce module ne lit pas les tables du portefeuille).
  // Une notification par cadeau, jamais retirée (le cadeau est définitif).
  | { type: 'gift'; actorId: string; recipientId: string; videoId: string; giftCode: string; giftAmount: number }
  // Live lancé (ADR-053, module live) : une notification par abonné et par live, jamais retirée (le live terminé reste
  // affiché comme tel) ; emportée avec le compte de son auteur.
  | { type: 'live'; actorId: string; recipientId: string; liveId: string };

// Actions réversibles : leur notification disparaît quand elles sont annulées (unlike, unfollow…).
// Un commentaire, une vidéo ou un compte supprimés emportent aussi les leurs (retirées juste avant, pour être annoncées).
export type RetractableActivity =
  Extract<ActivityEvent, { type: 'like' | 'repost' | 'follow' }> | { type: 'commentLike'; actorId: string; recipientId: string; commentId: string };

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
  // Notifications de cadeau seulement (ADR-050).
  gift: GiftDetails | null;
  // Notifications de live seulement (ADR-053).
  liveId: string | null;
  readAt: Date | null;
  createdAt: Date;
}

export interface GiftDetails {
  code: string;
  amount: number;
}

// Notification prête à afficher : auteur de l'action et vidéo, lus via les modules users et videos.
export interface NotificationWithContext {
  notification: Notification;
  // Nul pour une notification de modération.
  actor: User | null;
  // Null pour un follow.
  video: PublishedVideo | null;
}

// Regroupement à la lecture (choix du développeur, comme TikTok) : like, republication et cadeau par vidéo,
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

// Notification supprimée, annoncée à son destinataire pour la retirer de son groupe (ADR-043).
export interface RemovedNotification {
  id: string;
  key: string;
}

export function groupKey(notification: Notification): string {
  switch (notification.type) {
    case 'like':
    case 'repost':
    case 'gift':
      return `${notification.type}:${notification.videoId}`;
    case 'follow':
      return 'follow';
    // Chaque commentaire, réponse et mention seul (son texte compte).
    case 'comment':
    case 'commentReply':
    case 'mention':
    case 'videoMention':
      return `${notification.type}:${notification.id}`;
    // J'aime d'un commentaire : par commentaire (ADR-060).
    case 'commentLike':
      return `commentLike:${notification.commentId}`;
    // Chaque live seul.
    case 'live':
      return `live:${notification.liveId}`;
    // Modération : chaque notification seule.
    case 'reportResolved':
    case 'contentRemoved':
      return `moderation:${notification.id}`;
  }
}

// Groupe d'une notification qui peut en contenir d'autres (like, republication, follow), pour le recalculer après un
// retrait (ADR-043) ; null pour un groupe d'une seule notification (commentaire, modération), vide après son retrait.
export function groupFilter(notification: Notification): NotificationFilter | null {
  switch (notification.type) {
    case 'like':
    case 'repost':
    case 'gift':
      return { type: notification.type, videoId: notification.videoId ?? undefined };
    case 'follow':
      return { type: 'follow' };
    case 'commentLike':
      return { type: 'commentLike', commentId: notification.commentId ?? undefined };
    default:
      return null;
  }
}

// Notifications d'un groupe, pour sa liste complète : `type`, et la vidéo pour un like ou une republication, le
// commentaire pour un j'aime de commentaire (ADR-060).
export interface NotificationFilter {
  type?: NotificationType;
  videoId?: string;
  commentId?: string;
}

export const DEFAULT_NOTIFICATIONS_PAGE_SIZE = 20;
export const MAX_NOTIFICATIONS_PAGE_SIZE = 50;
