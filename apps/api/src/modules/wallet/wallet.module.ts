import { Module } from '@nestjs/common';
import { RealtimeModule } from '../realtime/realtime.module';
import { UsersService } from '../users/application/users.service';
import { UsersModule } from '../users/users.module';
import { WalletService } from './application/wallet.service';
import { WalletEventPublisher } from './domain/wallet-events';
import { WalletRepository } from './domain/wallet.repository';
import { AppWalletEventPublisher } from './infrastructure/app-wallet-event-publisher';
import { PrismaWalletRepository } from './infrastructure/prisma-wallet.repository';
import { RevenueCatWebhookController } from './interfaces/revenuecat-webhook.controller';
import { WalletController } from './interfaces/wallet.controller';
import { RevenueCatConfig } from './wallet.config';

// Portefeuille de jetons (ADR-009) : achats validés par RevenueCat, crédités par son webhook, solde tenu ici.
// Comptes lus via UsersService (ADR-003) ; solde poussé aux appareils par le module realtime (ADR-011).
@Module({
  imports: [UsersModule, RealtimeModule],
  controllers: [WalletController, RevenueCatWebhookController],
  providers: [
    { provide: RevenueCatConfig, useFactory: () => RevenueCatConfig.fromEnv() },
    { provide: WalletRepository, useClass: PrismaWalletRepository },
    { provide: WalletEventPublisher, useClass: AppWalletEventPublisher },
    {
      provide: WalletService,
      useFactory: (wallets: WalletRepository, users: UsersService, events: WalletEventPublisher, config: RevenueCatConfig) =>
        new WalletService(wallets, users, events, { rejectSandbox: config.rejectSandbox }),
      inject: [WalletRepository, UsersService, WalletEventPublisher, RevenueCatConfig],
    },
  ],
  exports: [WalletService],
})
export class WalletModule {}
