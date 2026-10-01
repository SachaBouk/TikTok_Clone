import { Module } from '@nestjs/common';
import { StorageConfig } from '../../storage/storage.config';
import { SuspendedAccounts } from '../../suspension/suspended-accounts';
import { VideosModule } from '../videos/videos.module';
import { UsersService } from './application/users.service';
import { AccountContentCleanup } from './domain/account-content-cleanup';
import { AvatarStorage } from './domain/avatar-storage';
import { UserRepository } from './domain/user.repository';
import { PrismaUserRepository } from './infrastructure/prisma-user.repository';
import { S3AvatarStorage } from './infrastructure/s3-avatar-storage';
import { VideoFilesAccountCleanup } from './infrastructure/video-files-account-cleanup';
import { UsersController } from './interfaces/users.controller';

// Câblage du module (ADR-003) : c'est le seul endroit où les ports sont reliés à leurs adaptateurs.
// Importe VideosModule pour nettoyer les fichiers vidéo d'un compte supprimé (videos ne dépend pas de users).
@Module({
  imports: [VideosModule],
  controllers: [UsersController],
  providers: [
    { provide: StorageConfig, useFactory: () => StorageConfig.fromEnv() },
    { provide: UserRepository, useClass: PrismaUserRepository },
    { provide: AvatarStorage, useFactory: (config: StorageConfig) => new S3AvatarStorage(config), inject: [StorageConfig] },
    { provide: AccountContentCleanup, useClass: VideoFilesAccountCleanup },
    {
      provide: UsersService,
      useFactory: (users: UserRepository, avatars: AvatarStorage, contentCleanup: AccountContentCleanup, suspended: SuspendedAccounts) =>
        new UsersService(users, avatars, contentCleanup, suspended),
      inject: [UserRepository, AvatarStorage, AccountContentCleanup, SuspendedAccounts],
    },
  ],
  exports: [UsersService],
})
export class UsersModule {}
