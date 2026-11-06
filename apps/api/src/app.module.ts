import { Module } from '@nestjs/common';
import { PrismaModule } from './database/prisma.module';
import { HealthController } from './health/health.controller';
import { AdminModule } from './modules/admin/admin.module';
import { AuthModule } from './modules/auth/auth.module';
import { CollectionsModule } from './modules/collections/collections.module';
import { CrossLiveModule } from './modules/crosslive/crosslive.module';
import { FeedModule } from './modules/feed/feed.module';
import { InteractionsModule } from './modules/interactions/interactions.module';
import { MessagingModule } from './modules/messaging/messaging.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { PushModule } from './modules/push/push.module';
import { RealtimeModule } from './modules/realtime/realtime.module';
import { ReportsModule } from './modules/reports/reports.module';
import { SearchModule } from './modules/search/search.module';
import { LiveModule } from './modules/live/live.module';
import { MuxWebhooksModule } from './modules/mux/mux-webhooks.module';
import { SubscriptionsModule } from './modules/subscriptions/subscriptions.module';
import { StoriesModule } from './modules/stories/stories.module';
import { UsersModule } from './modules/users/users.module';
import { VideosModule } from './modules/videos/videos.module';
import { WalletModule } from './modules/wallet/wallet.module';
import { RateLimitModule } from './rate-limit/rate-limit.module';
import { MuxModule } from './mux/mux.module';
import { PlusModule } from './plus/plus.module';
import { SuspensionModule } from './suspension/suspension.module';
import { RedisModule } from './redis/redis.module';

@Module({
  imports: [
    PrismaModule,
    RedisModule,
    RateLimitModule,
    SuspensionModule,
    PlusModule,
    MuxModule,
    AuthModule,
    UsersModule,
    VideosModule,
    InteractionsModule,
    CollectionsModule,
    StoriesModule,
    LiveModule,
    CrossLiveModule,
    NotificationsModule,
    FeedModule,
    SearchModule,
    MessagingModule,
    PushModule,
    RealtimeModule,
    WalletModule,
    SubscriptionsModule,
    ReportsModule,
    AdminModule,
    MuxWebhooksModule,
  ],
  controllers: [HealthController],
})
export class AppModule {}
