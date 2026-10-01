import { Module } from '@nestjs/common';
import { AuthService } from '../auth/application/auth.service';
import { AuthModule } from '../auth/auth.module';
import { InteractionsService } from '../interactions/application/interactions.service';
import { InteractionsModule } from '../interactions/interactions.module';
import { RealtimeService } from '../realtime/application/realtime.service';
import { RealtimeModule } from '../realtime/realtime.module';
import { UsersService } from '../users/application/users.service';
import { UsersModule } from '../users/users.module';
import { VideosService } from '../videos/application/videos.service';
import { VideosModule } from '../videos/videos.module';
import { WalletService } from '../wallet/application/wallet.service';
import { WalletModule } from '../wallet/wallet.module';
import { AdminService } from './application/admin.service';
import { AdminController } from './interfaces/admin.controller';

// Backoffice (ADR-004) : routes /admin réservées aux administrateurs. Aucune donnée propre : comptes,
// vidéos, commentaires et jetons sont lus et modérés via les services exportés des autres modules (ADR-003).
// Aucun module ne dépend de celui-ci.
@Module({
  imports: [AuthModule, UsersModule, VideosModule, InteractionsModule, WalletModule, RealtimeModule],
  controllers: [AdminController],
  providers: [
    {
      provide: AdminService,
      useFactory: (
        users: UsersService,
        videos: VideosService,
        interactions: InteractionsService,
        auth: AuthService,
        wallet: WalletService,
        realtime: RealtimeService,
      ) => new AdminService(users, videos, interactions, auth, wallet, realtime),
      inject: [UsersService, VideosService, InteractionsService, AuthService, WalletService, RealtimeService],
    },
  ],
})
export class AdminModule {}
