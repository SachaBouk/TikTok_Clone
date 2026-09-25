import type { Video } from '../domain/video';
import { VideoEventPublisher } from '../domain/video-events';

// Adaptateur en mémoire pour les tests : garde les événements publiés.
export class InMemoryVideoEventPublisher extends VideoEventPublisher {
  readonly processed: Video[] = [];

  async videoProcessed(video: Video): Promise<void> {
    this.processed.push(video);
  }
}
