import { Module } from '@nestjs/common';
import { CollectionsService } from '../collections/application/collections.service';
import { CollectionsModule } from '../collections/collections.module';
import { InteractionsService } from '../interactions/application/interactions.service';
import { InteractionsModule } from '../interactions/interactions.module';
import { StoriesService } from '../stories/application/stories.service';
import { StoriesModule } from '../stories/stories.module';
import { UsersService } from '../users/application/users.service';
import { UsersModule } from '../users/users.module';
import { VideosService } from '../videos/application/videos.service';
import { VideosModule } from '../videos/videos.module';
import { FeedService } from './application/feed.service';
import { FeedSnapshotStore } from './domain/feed-snapshot.store';
import { RedisFeedSnapshotStore } from './infrastructure/redis-feed-snapshot.store';
import { FeedController } from './interfaces/feed.controller';
import { CollectionVideosController } from './interfaces/collection-videos.controller';
import { HashtagVideosController } from './interfaces/hashtag-videos.controller';
import { ProfileVideosController } from './interfaces/profile-videos.controller';
import { SoundsController } from './interfaces/sounds.controller';

// Feed principal (ADR-016), cache Redis (ADR-014), feed des abonnements (ADR-048), grille d'un hashtag (ADR-049), sons de l'éditeur (ADR-064), grilles du profil (vidéos, republications, favoris) et vidéos d'une collection (ADR-072). Lit vidéos, auteurs, état du lecteur et anneaux de story (ADR-051) via les services exportés (ADR-003).
@Module({
  imports: [VideosModule, UsersModule, InteractionsModule, StoriesModule, CollectionsModule],
  controllers: [FeedController, ProfileVideosController, HashtagVideosController, SoundsController, CollectionVideosController],
  providers: [
    { provide: FeedSnapshotStore, useClass: RedisFeedSnapshotStore },
    {
      provide: FeedService,
      useFactory: (
        snapshots: FeedSnapshotStore,
        videos: VideosService,
        users: UsersService,
        interactions: InteractionsService,
        stories: StoriesService,
        collections: CollectionsService,
      ) => new FeedService(snapshots, videos, users, interactions, stories, collections),
      inject: [FeedSnapshotStore, VideosService, UsersService, InteractionsService, StoriesService, CollectionsService],
    },
  ],
})
export class FeedModule {}
