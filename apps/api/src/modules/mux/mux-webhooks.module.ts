import { Module } from '@nestjs/common';
import { StoriesService } from '../stories/application/stories.service';
import { StoriesModule } from '../stories/stories.module';
import { VideosService } from '../videos/application/videos.service';
import { VideosModule } from '../videos/videos.module';
import { MuxEventsService } from './application/mux-events.service';
import { MuxWebhookController } from './interfaces/mux-webhook.controller';

// Webhook de Mux (ADR-074) : module sans données ni couche `infrastructure/`, comme `admin` et `search`. Il dépend de
// `videos` et `stories` ; aucun module ne dépend de lui. Le client de Mux est dans `src/mux` (module global).
@Module({
  imports: [VideosModule, StoriesModule],
  controllers: [MuxWebhookController],
  providers: [
    {
      provide: MuxEventsService,
      useFactory: (videos: VideosService, stories: StoriesService) => new MuxEventsService(videos, stories),
      inject: [VideosService, StoriesService],
    },
  ],
})
export class MuxWebhooksModule {}
