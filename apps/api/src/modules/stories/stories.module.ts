import { Module } from '@nestjs/common';
import { RateLimiter } from '../../rate-limit/rate-limiter';
import { StorageConfig } from '../../storage/storage.config';
import { InteractionsService } from '../interactions/application/interactions.service';
import { InteractionsModule } from '../interactions/interactions.module';
import { RealtimeModule } from '../realtime/realtime.module';
import { UsersService } from '../users/application/users.service';
import { UsersModule } from '../users/users.module';
import { StoriesService } from './application/stories.service';
import { StoryEventPublisher } from './domain/story-events';
import { StoryLifecycleQueue, StoryTranscodingQueue } from './domain/story-queues';
import { StoryRepository } from './domain/story.repository';
import { StoryStorage } from './domain/story-storage';
import { AppStoryEventPublisher } from './infrastructure/app-story-event-publisher';
import { BullmqStoryLifecycleQueue, BullmqStoryTranscodingQueue } from './infrastructure/bullmq-story-queues';
import { PrismaStoryRepository } from './infrastructure/prisma-story.repository';
import { S3StoryStorage } from './infrastructure/s3-story-storage';
import { StoriesController, UserStoriesController } from './interfaces/stories.controller';
import {
  StoriesMaintenanceScheduler,
  StoryCleanupConsumer,
  StoryExpiryConsumer,
  StoryTranscodeResultsConsumer,
} from './interfaces/story-jobs.consumers';

// Stories (ADR-051), module ajouté à la liste de l'ADR-003. Comptes via UsersService, masquage et abonnements via
// InteractionsService, limites par le limiteur partagé (src/rate-limit), fin du transcodage par WebSocket (realtime).
// Inscrit le nettoyage des fichiers d'un compte supprimé auprès de UsersService (écouteur) : `users` ne dépend pas de
// `stories`. Exporte StoriesService pour feed (anneau), messaging (réponse), reports et admin (modération).
@Module({
  imports: [UsersModule, InteractionsModule, RealtimeModule],
  controllers: [StoriesController, UserStoriesController],
  providers: [
    { provide: StorageConfig, useFactory: () => StorageConfig.fromEnv() },
    { provide: StoryStorage, useFactory: (config: StorageConfig) => new S3StoryStorage(config), inject: [StorageConfig] },
    { provide: StoryRepository, useClass: PrismaStoryRepository },
    { provide: StoryTranscodingQueue, useClass: BullmqStoryTranscodingQueue },
    { provide: StoryLifecycleQueue, useClass: BullmqStoryLifecycleQueue },
    { provide: StoryEventPublisher, useClass: AppStoryEventPublisher },
    {
      provide: StoriesService,
      useFactory: (
        stories: StoryRepository,
        storage: StoryStorage,
        transcoding: StoryTranscodingQueue,
        lifecycle: StoryLifecycleQueue,
        events: StoryEventPublisher,
        users: UsersService,
        interactions: InteractionsService,
        rateLimiter: RateLimiter,
      ) => {
        const service = new StoriesService(stories, storage, transcoding, lifecycle, events, users, interactions, rateLimiter);
        users.onAccountDeleting(async (userId) => {
          await service.scheduleAuthorFilesCleanup(userId);
        });
        return service;
      },
      inject: [
        StoryRepository,
        StoryStorage,
        StoryTranscodingQueue,
        StoryLifecycleQueue,
        StoryEventPublisher,
        UsersService,
        InteractionsService,
        RateLimiter,
      ],
    },
    StoryTranscodeResultsConsumer,
    StoryExpiryConsumer,
    StoryCleanupConsumer,
    StoriesMaintenanceScheduler,
  ],
  exports: [StoriesService],
})
export class StoriesModule {}
