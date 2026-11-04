import { newUuidV7 } from '../../videos/domain/video-id';

// Identifiant UUID v7, choisi par le service avant la création : la clé d'une photo (`<storyId>/photo.jpg`) en dépend.
export function newStoryId(now: number = Date.now()): string {
  return newUuidV7(now);
}
