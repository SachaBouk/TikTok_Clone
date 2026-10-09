import { Module } from '@nestjs/common';
import { RateLimiter } from '../../rate-limit/rate-limiter';
import { InteractionsService } from '../interactions/application/interactions.service';
import { InteractionsModule } from '../interactions/interactions.module';
import { NotificationsService } from '../notifications/application/notifications.service';
import { NotificationsModule } from '../notifications/notifications.module';
import { UsersService } from '../users/application/users.service';
import { UsersModule } from '../users/users.module';
import { LiveService } from './application/live.service';
import { LiveLifecycleQueue, LiveMedia, LiveRoomPublisher } from './domain/live-media';
import { LiveRepository } from './domain/live.repository';
import { BullmqLiveLifecycleQueue } from './infrastructure/bullmq-live-lifecycle.queue';
import { LiveKitConfig } from './infrastructure/live.config';
import { LiveKitMedia, LiveKitRoomPublisher } from './infrastructure/livekit';
import { PrismaLiveRepository } from './infrastructure/prisma-live.repository';
import { LiveLifecycleConsumer, LiveMaintenanceScheduler } from './interfaces/live-jobs.consumers';
import { LiveController, UserLiveController } from './interfaces/live.controller';
import { LiveKitWebhookController } from './interfaces/livekit-webhook.controller';

// Live (ADR-053), module ajouté à la liste de l'ADR-003. Vidéo par le serveur LiveKit ; comptes via UsersService,
// abonnés, masquage et blocages via InteractionsService, abonnés prévenus via NotificationsService. Ferme la salle d'un
// compte supprimé (écouteur de UsersService : `users` ne dépend pas de `live`). Exporte LiveService pour wallet
// (cadeaux), messaging (live partagé), reports et admin (modération).
@Module({
  imports: [UsersModule, InteractionsModule, NotificationsModule],
  controllers: [LiveController, UserLiveController, LiveKitWebhookController],
  providers: [
    { provide: LiveKitConfig, useFactory: () => LiveKitConfig.fromEnv() },
    LiveKitMedia,
    { provide: LiveMedia, useExisting: LiveKitMedia },
    { provide: LiveRoomPublisher, useClass: LiveKitRoomPublisher },
    { provide: LiveLifecycleQueue, useClass: BullmqLiveLifecycleQueue },
    { provide: LiveRepository, useClass: PrismaLiveRepository },
    {
      provide: LiveService,
      useFactory: (
        lives: LiveRepository,
        media: LiveMedia,
        room: LiveRoomPublisher,
        lifecycle: LiveLifecycleQueue,
        users: UsersService,
        interactions: InteractionsService,
        notifications: NotificationsService,
        rateLimiter: RateLimiter,
      ) => {
        const service = new LiveService(lives, media, room, lifecycle, users, interactions, notifications, rateLimiter);
        users.onAccountDeleting((userId) => service.closeRoomsOf(userId));
        return service;
      },
      inject: [
        LiveRepository,
        LiveMedia,
        LiveRoomPublisher,
        LiveLifecycleQueue,
        UsersService,
        InteractionsService,
        NotificationsService,
        RateLimiter,
      ],
    },
    LiveLifecycleConsumer,
    LiveMaintenanceScheduler,
  ],
  exports: [LiveService],
})
export class LiveModule {}
