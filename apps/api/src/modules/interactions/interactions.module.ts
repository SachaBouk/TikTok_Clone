import { Module } from '@nestjs/common';
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
// Chaque interaction alimente le centre d'activité via NotificationsService.
@Module({
  imports: [VideosModule, UsersModule, NotificationsModule],
  controllers: [InteractionsController],
  providers: [
    { provide: InteractionRepository, useClass: PrismaInteractionRepository },
    {
      provide: InteractionsService,
      useFactory: (interactions: InteractionRepository, videos: VideosService, users: UsersService, notifications: NotificationsService) =>
        new InteractionsService(interactions, videos, users, notifications),
      inject: [InteractionRepository, VideosService, UsersService, NotificationsService],
    },
  ],
  exports: [InteractionsService],
})
export class InteractionsModule {}
