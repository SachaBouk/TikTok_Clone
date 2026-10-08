import { Module } from '@nestjs/common';
import { RateLimiter } from '../../rate-limit/rate-limiter';
import { SuspendedAccounts } from '../../suspension/suspended-accounts';
import { InteractionsService } from '../interactions/application/interactions.service';
import { InteractionsModule } from '../interactions/interactions.module';
import { MessagingService } from '../messaging/application/messaging.service';
import { MessagingModule } from '../messaging/messaging.module';
import { NotificationsService } from '../notifications/application/notifications.service';
import { NotificationsModule } from '../notifications/notifications.module';
import { StoriesService } from '../stories/application/stories.service';
import { StoriesModule } from '../stories/stories.module';
import { UsersService } from '../users/application/users.service';
import { UsersModule } from '../users/users.module';
import { VideosService } from '../videos/application/videos.service';
import { VideosModule } from '../videos/videos.module';
import { ReportsService } from './application/reports.service';
import { ModerationActionRepository } from './domain/moderation-action.repository';
import { ReportRepository } from './domain/report.repository';
import { PrismaModerationActionRepository } from './infrastructure/prisma-moderation-action.repository';
import { PrismaReportRepository } from './infrastructure/prisma-report.repository';
import { ReportsController } from './interfaces/reports.controller';

// Signalements et modération (ADR-038), module ajouté à la liste de l'ADR-003. Cibles vérifiées via UsersService,
// VideosService, InteractionsService, MessagingService et StoriesService (ADR-051) ; notifications de modération par NotificationsService ;
// limite par le limiteur partagé (src/rate-limit) ; comptes suspendus par le registre partagé (src/suspension).
// Exporte ReportsService pour le module admin (file de modération, décisions, journal). Aucun de ces modules ne
// dépend de reports.
@Module({
  imports: [UsersModule, VideosModule, InteractionsModule, MessagingModule, NotificationsModule, StoriesModule],
  controllers: [ReportsController],
  providers: [
    { provide: ReportRepository, useClass: PrismaReportRepository },
    { provide: ModerationActionRepository, useClass: PrismaModerationActionRepository },
    {
      provide: ReportsService,
      useFactory: (
        reports: ReportRepository,
        actions: ModerationActionRepository,
        users: UsersService,
        videos: VideosService,
        interactions: InteractionsService,
        messaging: MessagingService,
        notifications: NotificationsService,
        stories: StoriesService,
        rateLimiter: RateLimiter,
        suspended: SuspendedAccounts,
      ) => new ReportsService(reports, actions, users, videos, interactions, messaging, notifications, stories, rateLimiter, suspended),
      inject: [
        ReportRepository,
        ModerationActionRepository,
        UsersService,
        VideosService,
        InteractionsService,
        MessagingService,
        NotificationsService,
        StoriesService,
        RateLimiter,
        SuspendedAccounts,
      ],
    },
  ],
  exports: [ReportsService],
})
export class ReportsModule {}
