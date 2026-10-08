import type { Story } from './story';

// Port des événements envoyés à l'auteur (WebSocket, ADR-011) : fin du traitement d'une story vidéo.
export abstract class StoryEventPublisher {
  abstract storyProcessed(story: Story): Promise<void>;
}
