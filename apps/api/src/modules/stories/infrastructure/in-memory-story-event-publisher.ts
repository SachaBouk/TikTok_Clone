import type { Story } from '../domain/story';
import { StoryEventPublisher } from '../domain/story-events';

// Adaptateur en mémoire pour les tests : garde les événements envoyés.
export class InMemoryStoryEventPublisher extends StoryEventPublisher {
  readonly processed: Story[] = [];

  async storyProcessed(story: Story): Promise<void> {
    this.processed.push(story);
  }
}
