import { Module } from '@nestjs/common';
import { InteractionsService } from '../interactions/application/interactions.service';
import { InteractionsModule } from '../interactions/interactions.module';
import { UsersService } from '../users/application/users.service';
import { UsersModule } from '../users/users.module';
import { VideosService } from '../videos/application/videos.service';
import { VideosModule } from '../videos/videos.module';
import { CollectionsService } from './application/collections.service';
import { CollectionRepository } from './domain/collection.repository';
import { PrismaCollectionRepository } from './infrastructure/prisma-collection.repository';
import { CollectionsController } from './interfaces/collections.controller';

// Collections de favoris (ADR-072). Favoris et comptes masqués via InteractionsService, vidéos via VideosService,
// comptes via UsersService (ADR-003). Les modules feed (vidéos d'une collection) et messaging (carte partagée)
// dépendent de lui, jamais l'inverse.
@Module({
  imports: [InteractionsModule, VideosModule, UsersModule],
  controllers: [CollectionsController],
  providers: [
    { provide: CollectionRepository, useClass: PrismaCollectionRepository },
    {
      provide: CollectionsService,
      useFactory: (collections: CollectionRepository, interactions: InteractionsService, videos: VideosService, users: UsersService) =>
        new CollectionsService(collections, interactions, videos, users),
      inject: [CollectionRepository, InteractionsService, VideosService, UsersService],
    },
  ],
  exports: [CollectionsService],
})
export class CollectionsModule {}
