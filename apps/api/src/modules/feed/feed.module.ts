import { Module } from '@nestjs/common';
import { InteractionsService } from '../interactions/application/interactions.service';
import { InteractionsModule } from '../interactions/interactions.module';
import { UsersService } from '../users/application/users.service';
import { UsersModule } from '../users/users.module';
import { VideosService } from '../videos/application/videos.service';
import { VideosModule } from '../videos/videos.module';
import { FeedService } from './application/feed.service';
import { FeedSnapshotStore } from './domain/feed-snapshot.store';
import { RedisFeedSnapshotStore } from './infrastructure/redis-feed-snapshot.store';
import { FeedController } from './interfaces/feed.controller';
import { ProfileVideosController } from './interfaces/profile-videos.controller';

// Feed principal (ADR-016), cache Redis (ADR-014), et grilles du profil (vidéos, republications, favoris). Lit vidéos, auteurs et état du lecteur via les services exportés (ADR-003).
@Module({
  imports: [VideosModule, UsersModule, InteractionsModule],
  controllers: [FeedController, ProfileVideosController],
  providers: [
    { provide: FeedSnapshotStore, useClass: RedisFeedSnapshotStore },
    {
      provide: FeedService,
      useFactory: (snapshots: FeedSnapshotStore, videos: VideosService, users: UsersService, interactions: InteractionsService) =>
        new FeedService(snapshots, videos, users, interactions),
      inject: [FeedSnapshotStore, VideosService, UsersService, InteractionsService],
    },
  ],
})
export class FeedModule {}
