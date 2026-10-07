import { Module } from '@nestjs/common';
import { RateLimiter } from '../../rate-limit/rate-limiter';
import { InteractionsService } from '../interactions/application/interactions.service';
import { InteractionsModule } from '../interactions/interactions.module';
import { NotificationsService } from '../notifications/application/notifications.service';
import { NotificationsModule } from '../notifications/notifications.module';
import { RealtimeModule } from '../realtime/realtime.module';
import { UsersService } from '../users/application/users.service';
import { UsersModule } from '../users/users.module';
import { VideosService } from '../videos/application/videos.service';
import { VideosModule } from '../videos/videos.module';
import { WalletService } from './application/wallet.service';
import { WalletEventPublisher } from './domain/wallet-events';
import { WalletRepository } from './domain/wallet.repository';
import { AppWalletEventPublisher } from './infrastructure/app-wallet-event-publisher';
import { PrismaWalletRepository } from './infrastructure/prisma-wallet.repository';
import { GiftsController } from './interfaces/gifts.controller';
import { RevenueCatWebhookController } from './interfaces/revenuecat-webhook.controller';
import { WalletController } from './interfaces/wallet.controller';
import { RevenueCatConfig } from './wallet.config';

// Portefeuille de jetons (ADR-009) : achats validés par RevenueCat, crédités par son webhook, solde tenu ici.
// Cadeaux (ADR-050) : débités ici, vidéo et auteur lus via VideosService, masquage et blocages via InteractionsService,
// notification via NotificationsService (ADR-003) ; solde poussé aux appareils par le module realtime (ADR-011).
@Module({
  imports: [UsersModule, RealtimeModule, VideosModule, InteractionsModule, NotificationsModule],
  controllers: [WalletController, GiftsController, RevenueCatWebhookController],
  providers: [
    { provide: RevenueCatConfig, useFactory: () => RevenueCatConfig.fromEnv() },
    { provide: WalletRepository, useClass: PrismaWalletRepository },
    { provide: WalletEventPublisher, useClass: AppWalletEventPublisher },
    {
      provide: WalletService,
      useFactory: (
        wallets: WalletRepository,
        users: UsersService,
        events: WalletEventPublisher,
        config: RevenueCatConfig,
        videos: VideosService,
        interactions: InteractionsService,
        notifications: NotificationsService,
        rateLimiter: RateLimiter,
      ) => new WalletService(wallets, users, events, { rejectSandbox: config.rejectSandbox }, { videos, interactions, notifications, rateLimiter }),
      inject: [
        WalletRepository,
        UsersService,
        WalletEventPublisher,
        RevenueCatConfig,
        VideosService,
        InteractionsService,
        NotificationsService,
        RateLimiter,
      ],
    },
  ],
  exports: [WalletService],
})
export class WalletModule {}
