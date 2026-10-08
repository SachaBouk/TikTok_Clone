import { InMemoryRateLimiter } from '../../../rate-limit/in-memory-rate-limiter';
import type { InteractionsService } from '../../interactions/application/interactions.service';
import type { UsersService } from '../../users/application/users.service';
import { StoriesService } from '../application/stories.service';
import { InMemoryStoryEventPublisher } from './in-memory-story-event-publisher';
import { InMemoryStoryLifecycleQueue, InMemoryStoryTranscodingQueue } from './in-memory-story-queues';
import { InMemoryStoryRepository } from './in-memory-story.repository';
import { InMemoryStoryStorage } from './in-memory-story-storage';

// Service des stories avec tous ses adaptateurs en mémoire, pour les tests des modules qui en dépendent (messaging,
// reports, admin, feed) et pour les siens.
export function inMemoryStories(users: UsersService, interactions: InteractionsService, now: () => Date = () => new Date()) {
  const repository = new InMemoryStoryRepository(now);
  const storage = new InMemoryStoryStorage();
  const transcoding = new InMemoryStoryTranscodingQueue();
  const lifecycle = new InMemoryStoryLifecycleQueue();
  const events = new InMemoryStoryEventPublisher();
  const rateLimiter = new InMemoryRateLimiter(() => now().getTime());
  let sequence = 0;
  // Identifiants ordonnés (comme des UUID v7) et lisibles dans les tests.
  const makeId = () => `00000000-0000-7000-8000-${String(++sequence).padStart(12, '0')}`;
  const service = new StoriesService(repository, storage, transcoding, lifecycle, events, users, interactions, rateLimiter, now, makeId);
  return { service, repository, storage, transcoding, lifecycle, events, rateLimiter };
}

// En-tête JPEG minimal (début d'image puis SOF0) aux dimensions données : ce que l'API lit d'une photo envoyée.
export function jpegHeader(width: number, height: number): Uint8Array {
  return new Uint8Array([0xff, 0xd8, 0xff, 0xc0, 0x00, 0x11, 0x08, height >> 8, height & 0xff, width >> 8, width & 0xff, 0x03]);
}

// Publie une story comme le ferait l'app : envoi, confirmation, puis (vidéo) résultat du transcodage.
export async function publishTestStory(stories: ReturnType<typeof inMemoryStories>, userId: string, mediaType: 'photo' | 'video' = 'photo') {
  const fileSize = mediaType === 'photo' ? 1000 : 5000;
  const upload = await stories.service.createUpload(userId, { contentType: mediaType === 'photo' ? 'image/jpeg' : 'video/mp4', fileSize });
  if (mediaType === 'photo') stories.storage.contents.set(upload.story.rawKey, jpegHeader(1080, 1920));
  const uploadId = upload.story.uploadId!;
  const etag = stories.storage.putPart(uploadId, 1, fileSize);
  const story = await stories.service.completeUpload(userId, upload.story.id, [{ partNumber: 1, etag }]);
  if (mediaType === 'video') {
    await stories.service.applyTranscodeResult(story.id, {
      status: 'ready',
      mediaUrl: `https://cdn.test/${story.id}/master.m3u8`,
      thumbnailUrl: `https://cdn.test/${story.id}/thumbnail.jpg`,
    });
  }
  return (await stories.repository.findById(story.id))!;
}
