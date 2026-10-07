import { Injectable } from '@nestjs/common';
import { PUSH_BODY_MAX_LENGTH } from '../../push/domain/push';
import { PushService } from '../../push/application/push.service';
import { RealtimeService } from '../../realtime/application/realtime.service';
// Constantes du catalogue des cadeaux (nom, emoji), pas un accès aux données du portefeuille (ADR-003).
import { giftDisplay } from '../../wallet/domain/gift-catalog';
import type {
  ModerationOutcome,
  ModerationReason,
  ModerationTargetType,
  NotificationGroupWithContext,
  NotificationWithContext,
  RemovedNotification,
} from '../domain/notification';
import { NotificationPublisher } from '../domain/notification-publisher';
import { toNotificationDto, toNotificationGroupDto } from '../interfaces/notifications.responses';

// Prévient le destinataire sur ses appareils : WebSocket (module realtime, ADR-011), au même format que
// `GET /notifications`, et notification push (module push) pour une nouvelle notification.
@Injectable()
export class AppNotificationPublisher extends NotificationPublisher {
  constructor(
    private readonly realtime: RealtimeService,
    private readonly push: PushService,
  ) {
    super();
  }

  async notificationCreated(item: NotificationWithContext, unreadCount: number): Promise<void> {
    const { notification, actor } = item;
    await this.realtime.sendToUser(notification.recipientId, {
      event: 'notificationCreated',
      data: { notification: toNotificationDto(item), unreadCount },
    });
    await this.push.notify(notification.recipientId, {
      // Modération (ADR-038) : pas d'auteur.
      title: actor?.displayName ?? (notification.type === 'reportResolved' ? 'Signalement examiné' : 'Contenu retiré'),
      body: pushBody(item),
      threadId: 'activity',
      data: {
        type: 'notification',
        notificationId: notification.id,
        kind: notification.type,
        ...(notification.videoId ? { videoId: notification.videoId } : {}),
      },
    });
  }

  unreadCountChanged(recipientId: string, unreadCount: number): Promise<void> {
    return this.realtime.sendToUser(recipientId, { event: 'unreadNotificationsChanged', data: { unreadCount } });
  }

  // Pas de push : une notification retirée ne se signale qu'aux écrans ouverts. Groupes au format de `GET /notifications/groups`.
  notificationsRemoved(
    recipientId: string,
    removed: RemovedNotification[],
    groups: NotificationGroupWithContext[],
    unreadCount: number,
  ): Promise<void> {
    return this.realtime.sendToUser(recipientId, {
      event: 'notificationsRemoved',
      data: { removed: removed.map((r) => ({ id: r.id, key: r.key })), groups: groups.map(toNotificationGroupDto), unreadCount },
    });
  }
}

function pushBody({ notification }: NotificationWithContext): string {
  switch (notification.type) {
    case 'like':
      return 'a aimé ta vidéo';
    case 'repost':
      return 'a republié ta vidéo';
    case 'follow':
      return 'a commencé à te suivre';
    case 'comment':
      return `a commenté : ${notification.commentText ?? ''}`.slice(0, PUSH_BODY_MAX_LENGTH);
    case 'reportResolved':
      return outcomeText(notification.moderation?.outcome ?? 'dismissed');
    case 'contentRemoved':
      return `${REMOVED[notification.moderation?.targetType ?? 'video']} Motif : ${REASON_LABELS[notification.moderation?.reason ?? 'other']}.`;
    case 'gift': {
      const gift = giftDisplay(notification.gift?.code ?? '');
      return `t'a envoyé ${gift.emoji} ${gift.name}`;
    }
  }
}

// Textes en français des notifications de modération (mêmes libellés que l'app et le backoffice).
const REMOVED: Record<ModerationTargetType, string> = {
  video: 'Ta vidéo a été retirée.',
  comment: 'Ton commentaire a été retiré.',
  message: 'Ton message a été retiré.',
  // Un compte n'est pas « retiré » (suspension, annoncée à la connexion) : jamais envoyé.
  account: 'Ton compte a été suspendu.',
};
const REASON_LABELS: Record<ModerationReason, string> = {
  spam: 'spam',
  harassment: 'harcèlement',
  hate: 'contenu haineux',
  violence: 'violence',
  sexual: 'nudité ou contenu sexuel',
  impersonation: 'usurpation d’identité',
  other: 'non-respect des règles',
};

function outcomeText(outcome: ModerationOutcome): string {
  switch (outcome) {
    case 'contentRemoved':
      return 'Ton signalement a été examiné : le contenu a été retiré.';
    case 'accountSuspended':
      return 'Ton signalement a été examiné : le compte a été suspendu.';
    case 'dismissed':
      return 'Ton signalement a été examiné : aucune infraction constatée.';
  }
}
