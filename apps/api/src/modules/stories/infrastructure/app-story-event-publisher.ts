import { Injectable } from '@nestjs/common';
import { RealtimeService } from '../../realtime/application/realtime.service';
import type { Story } from '../domain/story';
import { StoryEventPublisher } from '../domain/story-events';
import { toStoryDto } from '../interfaces/stories.responses';

// Prévient l'auteur sur ses appareils par WebSocket (module realtime, ADR-011), au même format que l'API REST. Pas de
// notification push : la publication d'une story ne prend que quelques secondes.
@Injectable()
export class AppStoryEventPublisher extends StoryEventPublisher {
  constructor(private readonly realtime: RealtimeService) {
    super();
  }

  async storyProcessed(story: Story): Promise<void> {
    await this.realtime.sendToUser(story.userId, { event: 'storyProcessed', data: toStoryDto(story) });
  }
}
