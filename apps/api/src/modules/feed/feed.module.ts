import { Module } from '@nestjs/common';
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
import { HashtagVideosController } from './interfaces/hashtag-videos.controller';
import { ProfileVideosController } from './interfaces/profile-videos.controller';
import { SoundsController } from './interfaces/sounds.controller';

// Feed principal (ADR-016), cache Redis (ADR-014), feed des abonnements (ADR-048), grille d'un hashtag (ADR-049), sons de l'éditeur (ADR-064) et grilles du profil (vidéos, republications, favoris). Lit vidéos, auteurs, état du lecteur et anneaux de story (ADR-051) via les services exportés (ADR-003).
@Module({
  imports: [VideosModule, UsersModule, InteractionsModule, StoriesModule],
  controllers: [FeedController, ProfileVideosController, HashtagVideosController, SoundsController],
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
      ) => new FeedService(snapshots, videos, users, interactions, stories),
      inject: [FeedSnapshotStore, VideosService, UsersService, InteractionsService, StoriesService],
    },
  ],
})
export class FeedModule {}
