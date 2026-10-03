import { Module } from '@nestjs/common';
import { SuspendedAccounts } from '../../suspension/suspended-accounts';
import { PushModule } from '../push/push.module';
import { RealtimeModule } from '../realtime/realtime.module';
import { UsersService } from '../users/application/users.service';
import { UsersModule } from '../users/users.module';
import { VideosService } from '../videos/application/videos.service';
import { VideosModule } from '../videos/videos.module';
import { NotificationsService } from './application/notifications.service';
import { NotificationPublisher } from './domain/notification-publisher';
import { NotificationRepository } from './domain/notification.repository';
import { PrismaNotificationRepository } from './infrastructure/prisma-notification.repository';
import { AppNotificationPublisher } from './infrastructure/app-notification-publisher';
import { NotificationsController } from './interfaces/notifications.controller';

// Centre d'activité (ADR-016). Alimenté par le module interactions via le service exporté (ADR-003) ;
// auteurs et vidéos lus via les services de `users` et `videos`. Ne dépend pas d'interactions (pas de cycle).
// Nouvelles notifications et badge poussés en direct par le module realtime (ADR-011), et en notification push.
// Prévenu par `videos` et `users` avant la suppression d'une vidéo ou d'un compte (écouteurs, sans dépendance inverse).
@Module({
  imports: [UsersModule, VideosModule, RealtimeModule, PushModule],
  controllers: [NotificationsController],
  providers: [
    { provide: NotificationRepository, useClass: PrismaNotificationRepository },
    { provide: NotificationPublisher, useClass: AppNotificationPublisher },
    {
      provide: NotificationsService,
      useFactory: (
        notifications: NotificationRepository,
        users: UsersService,
        videos: VideosService,
        publisher: NotificationPublisher,
        suspended: SuspendedAccounts,
      ) => {
        const service = new NotificationsService(notifications, users, videos, publisher, suspended);
        // Vidéo ou compte supprimés : leurs notifications sont retirées et annoncées avant la cascade (ADR-043).
        videos.onVideoRemoving((videoId) => service.retractVideo(videoId));
        users.onAccountDeleting((userId) => service.retractActor(userId));
        return service;
      },
      inject: [NotificationRepository, UsersService, VideosService, NotificationPublisher, SuspendedAccounts],
    },
  ],
  exports: [NotificationsService],
})
export class NotificationsModule {}
