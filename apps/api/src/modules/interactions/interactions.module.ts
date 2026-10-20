import { Logger, Module } from '@nestjs/common';
import { RateLimiter } from '../../rate-limit/rate-limiter';
import { SuspendedAccounts } from '../../suspension/suspended-accounts';
import { NotificationsService } from '../notifications/application/notifications.service';
import { NotificationsModule } from '../notifications/notifications.module';
import { RealtimeModule } from '../realtime/realtime.module';
import { UsersService } from '../users/application/users.service';
import { UsersModule } from '../users/users.module';
import { VideosService } from '../videos/application/videos.service';
import { VideosModule } from '../videos/videos.module';
import { InteractionsService } from './application/interactions.service';
import { InteractionRepository } from './domain/interaction.repository';
import { ProfileCountersPublisher } from './domain/profile-counters-publisher';
import { AppProfileCountersPublisher } from './infrastructure/app-profile-counters-publisher';
import { PrismaInteractionRepository } from './infrastructure/prisma-interaction.repository';
import { InteractionsController } from './interfaces/interactions.controller';

// Interactions sociales (ADR-016) : like, favori, republication, partage, commentaire, follow.
// Vidéos et comptes lus via les services exportés (ADR-003) ; compteurs maintenus par les triggers de la base.
// Chaque interaction alimente le centre d'activité via NotificationsService. Partages comptés dédoublonnés
// par le limiteur partagé (src/rate-limit, ADR-030). Compteurs du profil poussés en direct après un abonnement
// (ADR-045, module realtime).
@Module({
  imports: [VideosModule, UsersModule, NotificationsModule, RealtimeModule],
  controllers: [InteractionsController],
  providers: [
    { provide: InteractionRepository, useClass: PrismaInteractionRepository },
    { provide: ProfileCountersPublisher, useClass: AppProfileCountersPublisher },
    {
      provide: InteractionsService,
      useFactory: (
        interactions: InteractionRepository,
        videos: VideosService,
        users: UsersService,
        notifications: NotificationsService,
        rateLimiter: RateLimiter,
        suspended: SuspendedAccounts,
        counters: ProfileCountersPublisher,
      ) => {
        const service = new InteractionsService(interactions, videos, users, notifications, rateLimiter, suspended, counters);
        // Vidéo publiée : les comptes mentionnés dans sa description sont prévenus (ADR-065). Au mieux : un échec est
        // journalisé, la publication reste acquise.
        const logger = new Logger('VideoMentions');
        videos.onVideoPublished(async (video) => {
          try {
            await service.notifyVideoMentions(video);
          } catch (error) {
            logger.warn(`Mentions de la vidéo ${video.id} non envoyées : ${error instanceof Error ? error.message : String(error)}`);
          }
        });
        return service;
      },
      inject: [InteractionRepository, VideosService, UsersService, NotificationsService, RateLimiter, SuspendedAccounts, ProfileCountersPublisher],
    },
  ],
  exports: [InteractionsService],
})
export class InteractionsModule {}
