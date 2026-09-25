import { Module } from '@nestjs/common';
import { InteractionsService } from '../interactions/application/interactions.service';
import { InteractionsModule } from '../interactions/interactions.module';
import { PushModule } from '../push/push.module';
import { RealtimeModule } from '../realtime/realtime.module';
import { UsersService } from '../users/application/users.service';
import { UsersModule } from '../users/users.module';
import { VideosService } from '../videos/application/videos.service';
import { VideosModule } from '../videos/videos.module';
import { MessagingService } from './application/messaging.service';
import { ConversationRepository } from './domain/conversation.repository';
import { MessagingEventPublisher } from './domain/messaging-event-publisher';
import { RateLimiter } from './domain/rate-limiter';
import { AppMessagingEventPublisher } from './infrastructure/app-messaging-event-publisher';
import { PrismaConversationRepository } from './infrastructure/prisma-conversation.repository';
import { RedisRateLimiter } from './infrastructure/redis-rate-limiter';
import { MessagingController } from './interfaces/messaging.controller';
import { MessagingRealtimeHandlers } from './interfaces/messaging-realtime.handlers';

// Messagerie directe (ADR-016), module ajouté à la liste de l'ADR-003. Comptes via UsersService, follows
// mutuels et blocages via InteractionsService, vidéos partagées via VideosService ; événements par le module
// realtime (ADR-011) et notifications push par le module push ; limites d'envoi dans Redis (ADR-014).
@Module({
  imports: [UsersModule, InteractionsModule, VideosModule, RealtimeModule, PushModule],
  controllers: [MessagingController],
  providers: [
    { provide: ConversationRepository, useClass: PrismaConversationRepository },
    { provide: MessagingEventPublisher, useClass: AppMessagingEventPublisher },
    { provide: RateLimiter, useClass: RedisRateLimiter },
    {
      provide: MessagingService,
      useFactory: (
        conversations: ConversationRepository,
        users: UsersService,
        interactions: InteractionsService,
        videos: VideosService,
        events: MessagingEventPublisher,
        rateLimiter: RateLimiter,
      ) => new MessagingService(conversations, users, interactions, videos, events, rateLimiter),
      inject: [ConversationRepository, UsersService, InteractionsService, VideosService, MessagingEventPublisher, RateLimiter],
    },
    MessagingRealtimeHandlers,
  ],
  exports: [MessagingService],
})
export class MessagingModule {}
