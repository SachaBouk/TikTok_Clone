import { Module } from '@nestjs/common';
import { InteractionsService } from '../interactions/application/interactions.service';
import { InteractionsModule } from '../interactions/interactions.module';
import { UsersService } from '../users/application/users.service';
import { UsersModule } from '../users/users.module';
import { VideosService } from '../videos/application/videos.service';
import { VideosModule } from '../videos/videos.module';
import { SearchService } from './application/search.service';
import { HashtagsController, SearchController } from './interfaces/search.controller';

// Recherche de comptes et hashtags (ADR-049). Aucune donnée propre, comme admin : comptes, relations et hashtags
// passent par les services exportés des modules users, interactions et videos (ADR-003). Aucun module n'en dépend.
@Module({
  imports: [UsersModule, InteractionsModule, VideosModule],
  controllers: [SearchController, HashtagsController],
  providers: [
    {
      provide: SearchService,
      useFactory: (users: UsersService, interactions: InteractionsService, videos: VideosService) => new SearchService(users, interactions, videos),
      inject: [UsersService, InteractionsService, VideosService],
    },
  ],
})
export class SearchModule {}
