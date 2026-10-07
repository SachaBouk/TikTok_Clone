import type { ReportReason, ReportTargetType } from './reports.js';
import type { UserSummaryDto } from './users.js';

// Centre d'activité (ADR-016) : ce que les autres comptes ont fait sur mes vidéos et mon compte.

// `reportResolved` et `contentRemoved` : modération (ADR-038), sans auteur. `gift` : cadeau reçu sur une vidéo (ADR-050).
export type NotificationType = 'like' | 'comment' | 'follow' | 'repost' | 'reportResolved' | 'contentRemoved' | 'gift';

// Cadeau reçu (ADR-050) : code du catalogue, nom et emoji (« 🎁 Cadeau » pour un code retiré depuis), prix payé.
export interface NotificationGiftDto {
  code: string;
  name: string;
  emoji: string;
  amount: number;
}

// Décision sur un signalement, annoncée à la personne qui l'a envoyé.
export type ModerationOutcome = 'contentRemoved' | 'accountSuspended' | 'dismissed';

// Notification de modération : contenu concerné, motif (contenu retiré) ou décision (signalement examiné), texte copié.
export interface NotificationModerationDto {
  targetType: ReportTargetType;
  reason?: ReportReason;
  outcome?: ModerationOutcome;
  excerpt?: string;
}

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
  // Auteur de l'action ; absent pour une notification de modération.
  actor?: UserSummaryDto;
  // Absent pour un follow (plutôt que null : voir FeedItemDto.viewer).
  video?: NotificationVideoDto;
  // Présent pour un commentaire seulement.
  comment?: NotificationCommentDto;
  // Présent pour une notification de modération seulement.
  moderation?: NotificationModerationDto;
  // Présent pour un cadeau seulement.
  gift?: NotificationGiftDto;
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
// like, republication et cadeau par vidéo, tous les follows ensemble, chaque commentaire seul.
export interface NotificationGroupDto {
  // Identifiant stable du groupe : `like:<videoId>`, `repost:<videoId>`, `gift:<videoId>`, `follow`,
  // `comment:<notificationId>`, `moderation:<notificationId>`.
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
  // Notification de modération (toujours seule, sans auteur : `actors` vide).
  moderation?: NotificationModerationDto;
  // Cadeau de la notification la plus récente du groupe (cadeaux regroupés par vidéo).
  gift?: NotificationGiftDto;
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
