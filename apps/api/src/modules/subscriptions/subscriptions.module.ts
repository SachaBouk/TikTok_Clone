import { Module } from '@nestjs/common';
import { PlusMembers } from '../../plus/plus-members';
import { RealtimeModule } from '../realtime/realtime.module';
import { UsersService } from '../users/application/users.service';
import { UsersModule } from '../users/users.module';
import { SubscriptionsService } from './application/subscriptions.service';
import { PlusEventPublisher } from './domain/plus-events';
import { PlusSubscriptionRepository } from './domain/plus-subscription.repository';
import { RevenueCatCustomers } from './domain/revenuecat-customers';
import { AppPlusEventPublisher } from './infrastructure/app-plus-event-publisher';
import { HttpRevenueCatCustomers } from './infrastructure/http-revenuecat-customers';
import { PlusMembersSync } from './infrastructure/plus-members-sync';
import { PrismaPlusSubscriptionRepository } from './infrastructure/prisma-plus-subscription.repository';
import { SubscriptionsController } from './interfaces/subscriptions.controller';
import { SubscriptionsConfig } from './subscriptions.config';

// Abonnement « Plus » (ADR-073) : état relu chez RevenueCat à chaque webhook (reçu par le module wallet), gardé en base
// et dans le registre partagé `PlusMembers`, lu par users, videos, live et wallet sans dépendre de ce module.
@Module({
  imports: [UsersModule, RealtimeModule],
  controllers: [SubscriptionsController],
  providers: [
    { provide: SubscriptionsConfig, useFactory: () => SubscriptionsConfig.fromEnv() },
    { provide: PlusSubscriptionRepository, useClass: PrismaPlusSubscriptionRepository },
    { provide: RevenueCatCustomers, useClass: HttpRevenueCatCustomers },
    { provide: PlusEventPublisher, useClass: AppPlusEventPublisher },
    {
      provide: SubscriptionsService,
      useFactory: (
        subscriptions: PlusSubscriptionRepository,
        customers: RevenueCatCustomers,
        users: UsersService,
        plus: PlusMembers,
        events: PlusEventPublisher,
        config: SubscriptionsConfig,
      ) => new SubscriptionsService(subscriptions, customers, users, plus, events, { rejectSandbox: config.rejectSandbox }),
      inject: [PlusSubscriptionRepository, RevenueCatCustomers, UsersService, PlusMembers, PlusEventPublisher, SubscriptionsConfig],
    },
    PlusMembersSync,
  ],
  exports: [SubscriptionsService],
})
export class SubscriptionsModule {}
