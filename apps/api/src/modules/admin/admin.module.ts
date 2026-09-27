import { Module } from '@nestjs/common';
import { AuthService } from '../auth/application/auth.service';
import { AuthModule } from '../auth/auth.module';
import { InteractionsService } from '../interactions/application/interactions.service';
import { InteractionsModule } from '../interactions/interactions.module';
import { UsersService } from '../users/application/users.service';
import { UsersModule } from '../users/users.module';
import { VideosService } from '../videos/application/videos.service';
import { VideosModule } from '../videos/videos.module';
import { AdminService } from './application/admin.service';
import { AdminController } from './interfaces/admin.controller';

// Backoffice (ADR-004) : routes /admin réservées aux administrateurs. Aucune donnée propre : comptes,
// vidéos et commentaires sont lus et modérés via les services exportés des autres modules (ADR-003).
// Aucun module ne dépend de celui-ci.
@Module({
  imports: [AuthModule, UsersModule, VideosModule, InteractionsModule],
  controllers: [AdminController],
  providers: [
    {
      provide: AdminService,
      useFactory: (users: UsersService, videos: VideosService, interactions: InteractionsService, auth: AuthService) =>
        new AdminService(users, videos, interactions, auth),
      inject: [UsersService, VideosService, InteractionsService, AuthService],
    },
  ],
})
export class AdminModule {}
