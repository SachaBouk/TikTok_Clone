import { Module } from '@nestjs/common';
import { PrismaModule } from './database/prisma.module';
import { HealthController } from './health/health.controller';
import { AdminModule } from './modules/admin/admin.module';
import { AuthModule } from './modules/auth/auth.module';
import { FeedModule } from './modules/feed/feed.module';
import { InteractionsModule } from './modules/interactions/interactions.module';
import { MessagingModule } from './modules/messaging/messaging.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { PushModule } from './modules/push/push.module';
import { RealtimeModule } from './modules/realtime/realtime.module';
import { UsersModule } from './modules/users/users.module';
import { VideosModule } from './modules/videos/videos.module';
import { WalletModule } from './modules/wallet/wallet.module';
import { RateLimitModule } from './rate-limit/rate-limit.module';
import { RedisModule } from './redis/redis.module';

@Module({
  imports: [PrismaModule, RedisModule, RateLimitModule, AuthModule, UsersModule, VideosModule, InteractionsModule, NotificationsModule, FeedModule, MessagingModule, PushModule, RealtimeModule, WalletModule, AdminModule],
  controllers: [HealthController],
})
export class AppModule {}
