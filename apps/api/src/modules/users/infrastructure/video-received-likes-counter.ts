import { Injectable } from '@nestjs/common';
import { VideosService } from '../../videos/application/videos.service';
import { ReceivedLikesCounter } from '../domain/received-likes-counter';

// Adaptateur : somme des likes des vidéos publiées du compte, lue par le module videos (ADR-003).
@Injectable()
export class VideoReceivedLikesCounter extends ReceivedLikesCounter {
  constructor(private readonly videos: VideosService) {
    super();
  }

  countFor(userId: string): Promise<number> {
    return this.videos.countLikesReceived(userId);
  }
}
