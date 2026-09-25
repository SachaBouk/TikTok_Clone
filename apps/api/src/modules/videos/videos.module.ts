import { Module } from '@nestjs/common';
import { PushModule } from '../push/push.module';
import { RealtimeModule } from '../realtime/realtime.module';
import { VideosService } from './application/videos.service';
import { VideoCleanupQueue } from './domain/cleanup-queue';
import { TranscodingQueue } from './domain/transcoding-queue';
import { VideoEventPublisher } from './domain/video-events';
import { VideoRepository } from './domain/video.repository';
import { VideoStorage } from './domain/video-storage';
import { BullmqTranscodingQueue } from './infrastructure/bullmq-transcoding-queue';
import { BullmqVideoCleanupQueue } from './infrastructure/bullmq-video-cleanup-queue';
import { PrismaVideoRepository } from './infrastructure/prisma-video.repository';
import { AppVideoEventPublisher } from './infrastructure/app-video-event-publisher';
import { S3VideoStorage } from './infrastructure/s3-video-storage';
import { TranscodeResultsConsumer } from './interfaces/transcode-results.consumer';
import { VideoCleanupConsumer } from './interfaces/video-cleanup.consumer';
import { MyVideosController } from './interfaces/my-videos.controller';
import { VideosController } from './interfaces/videos.controller';
import { VideosMaintenanceScheduler } from './interfaces/videos-maintenance.scheduler';
import { StorageConfig } from '../../storage/storage.config';

// Vidéos : upload direct (ADR-007), transcodage asynchrone via BullMQ (ADR-012) par apps/worker (ADR-008).
// Fin du transcodage envoyée à l'auteur par WebSocket (module realtime, ADR-011) et notification push.
@Module({
  imports: [RealtimeModule, PushModule],
  controllers: [VideosController, MyVideosController],
  providers: [
    { provide: StorageConfig, useFactory: () => StorageConfig.fromEnv() },
    { provide: VideoStorage, useFactory: (config: StorageConfig) => new S3VideoStorage(config), inject: [StorageConfig] },
    { provide: VideoRepository, useClass: PrismaVideoRepository },
    { provide: TranscodingQueue, useClass: BullmqTranscodingQueue },
    { provide: VideoEventPublisher, useClass: AppVideoEventPublisher },
    { provide: VideoCleanupQueue, useClass: BullmqVideoCleanupQueue },
    {
      provide: VideosService,
      useFactory: (
        videos: VideoRepository,
        storage: VideoStorage,
        transcoding: TranscodingQueue,
        events: VideoEventPublisher,
        cleanup: VideoCleanupQueue,
      ) => new VideosService(videos, storage, transcoding, events, cleanup),
      inject: [VideoRepository, VideoStorage, TranscodingQueue, VideoEventPublisher, VideoCleanupQueue],
    },
    TranscodeResultsConsumer,
    VideoCleanupConsumer,
    VideosMaintenanceScheduler,
  ],
  exports: [VideosService],
})
export class VideosModule {}
