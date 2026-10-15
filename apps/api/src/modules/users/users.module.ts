import { Module } from '@nestjs/common';
import { StorageConfig } from '../../storage/storage.config';
import { SuspendedAccounts } from '../../suspension/suspended-accounts';
import { VideosModule } from '../videos/videos.module';
import { UsersService } from './application/users.service';
import { AccountContentCleanup } from './domain/account-content-cleanup';
import { AvatarStorage } from './domain/avatar-storage';
import { InterestRepository } from './domain/interest.repository';
import { ReceivedLikesCounter } from './domain/received-likes-counter';
import { UserRepository } from './domain/user.repository';
import { PrismaInterestRepository } from './infrastructure/prisma-interest.repository';
import { PrismaUserRepository } from './infrastructure/prisma-user.repository';
import { S3AvatarStorage } from './infrastructure/s3-avatar-storage';
import { VideoReceivedLikesCounter } from './infrastructure/video-received-likes-counter';
import { VideoFilesAccountCleanup } from './infrastructure/video-files-account-cleanup';
import { InterestsController } from './interfaces/interests.controller';
import { UsersController } from './interfaces/users.controller';

// Câblage du module (ADR-003) : c'est le seul endroit où les ports sont reliés à leurs adaptateurs.
// Importe VideosModule pour nettoyer les fichiers vidéo d'un compte supprimé et compter ses likes reçus (videos ne
// dépend pas de users).
@Module({
  imports: [VideosModule],
  controllers: [UsersController, InterestsController],
  providers: [
    { provide: StorageConfig, useFactory: () => StorageConfig.fromEnv() },
    { provide: UserRepository, useClass: PrismaUserRepository },
    { provide: AvatarStorage, useFactory: (config: StorageConfig) => new S3AvatarStorage(config), inject: [StorageConfig] },
    { provide: AccountContentCleanup, useClass: VideoFilesAccountCleanup },
    { provide: InterestRepository, useClass: PrismaInterestRepository },
    { provide: ReceivedLikesCounter, useClass: VideoReceivedLikesCounter },
    {
      provide: UsersService,
      useFactory: (
        users: UserRepository,
        avatars: AvatarStorage,
        contentCleanup: AccountContentCleanup,
        interests: InterestRepository,
        suspended: SuspendedAccounts,
        receivedLikes: ReceivedLikesCounter,
      ) => new UsersService(users, avatars, contentCleanup, interests, suspended, receivedLikes),
      inject: [UserRepository, AvatarStorage, AccountContentCleanup, InterestRepository, SuspendedAccounts, ReceivedLikesCounter],
    },
  ],
  exports: [UsersService],
})
export class UsersModule {}
