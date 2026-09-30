import { Module } from '@nestjs/common';
import { RateLimiter } from '../../rate-limit/rate-limiter';
import { NotificationsService } from '../notifications/application/notifications.service';
import { NotificationsModule } from '../notifications/notifications.module';
import { UsersService } from '../users/application/users.service';
import { UsersModule } from '../users/users.module';
import { VideosService } from '../videos/application/videos.service';
import { VideosModule } from '../videos/videos.module';
import { InteractionsService } from './application/interactions.service';
import { InteractionRepository } from './domain/interaction.repository';
import { PrismaInteractionRepository } from './infrastructure/prisma-interaction.repository';
import { InteractionsController } from './interfaces/interactions.controller';

// Interactions sociales (ADR-016) : like, favori, republication, partage, commentaire, follow.
// Vidéos et comptes lus via les services exportés (ADR-003) ; compteurs maintenus par les triggers de la base.
// Chaque interaction alimente le centre d'activité via NotificationsService. Partages comptés dédoublonnés
// par le limiteur partagé (src/rate-limit, ADR-030).
@Module({
  imports: [VideosModule, UsersModule, NotificationsModule],
  controllers: [InteractionsController],
  providers: [
    { provide: InteractionRepository, useClass: PrismaInteractionRepository },
    {
      provide: InteractionsService,
      useFactory: (
        interactions: InteractionRepository,
        videos: VideosService,
        users: UsersService,
        notifications: NotificationsService,
        rateLimiter: RateLimiter,
      ) => new InteractionsService(interactions, videos, users, notifications, rateLimiter),
      inject: [InteractionRepository, VideosService, UsersService, NotificationsService, RateLimiter],
    },
  ],
  exports: [InteractionsService],
})
export class InteractionsModule {}
