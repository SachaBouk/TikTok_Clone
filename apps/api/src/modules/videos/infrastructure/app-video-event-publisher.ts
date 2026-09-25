import { Injectable } from '@nestjs/common';
import { PushService } from '../../push/application/push.service';
import { RealtimeService } from '../../realtime/application/realtime.service';
import type { Video } from '../domain/video';
import { VideoEventPublisher } from '../domain/video-events';
import { toVideoDto } from '../interfaces/videos.responses';

// Prévient l'auteur sur ses appareils : WebSocket (module realtime, ADR-011), au même format que l'API REST,
// et notification push (module push).
@Injectable()
export class AppVideoEventPublisher extends VideoEventPublisher {
  constructor(
    private readonly realtime: RealtimeService,
    private readonly push: PushService,
  ) {
    super();
  }

  async videoProcessed(video: Video): Promise<void> {
    await this.realtime.sendToUser(video.userId, { event: 'videoProcessed', data: toVideoDto(video) });
    await this.push.notify(video.userId, {
      title: video.status === 'ready' ? 'Vidéo publiée' : 'Échec de la publication',
      body: video.status === 'ready' ? 'Ta vidéo est en ligne.' : 'Ta vidéo n’a pas pu être traitée. Réessaie avec un autre fichier.',
      threadId: 'videos',
      data: { type: 'videoProcessed', videoId: video.id, status: video.status },
    });
  }
}
