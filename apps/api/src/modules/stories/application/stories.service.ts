import type { InteractionsService } from '../../interactions/application/interactions.service';
import type { UsersService } from '../../users/application/users.service';
import type { User } from '../../users/domain/user';
import { UserNotFoundError } from '../../users/domain/user.errors';
import { partCount, UPLOAD_PART_SIZE_BYTES, UPLOAD_RATE_LIMITS, UPLOAD_URL_TTL_SECONDS, uploadRateLimitKey } from '../../videos/domain/upload-rules';
import type { RateLimiter } from '../../../rate-limit/rate-limiter';
import {
  type ActiveStory,
  DEFAULT_VIEWERS_PAGE_SIZE,
  filesOf,
  isActive,
  isSupportedStoryType,
  isValidStoryPhoto,
  MAX_ACTIVE_STORIES,
  MAX_TRAY_ACCOUNTS,
  maxStorySize,
  mediaTypeOf,
  PHOTO_STORY_RATE_LIMITS,
  type Story,
  STORY_LIFETIME_MS,
  STORY_LIKE_RATE_LIMITS,
  STORY_MAINTENANCE_BATCH_SIZE,
  STORY_PHOTO_HEADER_LENGTH,
  STORY_VIEW_RATE_LIMITS,
  type StoryFiles,
  type StoryStats,
  type StoryTranscodeOutcome,
  storyRawKey,
  STUCK_STORY_TRANSCODE_AFTER_MS,
  UNPUBLISHED_STORY_TTL_MS,
} from '../domain/story';
import {
  InvalidStoryCursorError,
  InvalidStoryPhotoError,
  OwnStoryError,
  StoryAuthorNotFoundError,
  StoryNotAwaitingUploadError,
  StoryNotFoundError,
  StoryTooLargeError,
  StoryUploadIncompleteError,
  TooManyActiveStoriesError,
  TooManyStoryActionsError,
  UnsupportedStoryTypeError,
} from '../domain/story.errors';
import type { StoryEventPublisher } from '../domain/story-events';
import { newStoryId } from '../domain/story-id';
import { STORY_CLEANUP_DELAY_MS, type StoryLifecycleQueue, type StoryTranscodingQueue } from '../domain/story-queues';
import type { StoryRepository } from '../domain/story.repository';
import type { PresignedPart, StoryBucket, StoryStorage, UploadedPart } from '../domain/story-storage';
import { decodeViewersCursor, encodeViewersCursor } from '../domain/viewers-cursor';

export interface CreateStoryUploadInput {
  contentType: string;
  fileSize: number;
}

export interface StoryUpload {
  story: Story;
  partSize: number;
  parts: PresignedPart[];
  expiresAt: Date;
}

// Une story active telle qu'un compte la voit : son état (vue, aimée) s'il est connecté, ses chiffres s'il en est l'auteur.
export interface StoryItem {
  story: ActiveStory;
  viewer?: { viewed: boolean; liked: boolean };
  stats?: StoryStats;
}

export interface UserStories {
  user: User;
  items: StoryItem[];
}

export interface StoryTrayEntry {
  user: User;
  storiesCount: number;
  latestAt: Date;
  hasUnseen: boolean;
}

export interface StoryViewerEntry {
  user: User;
  viewedAt: Date;
  liked: boolean;
}

export interface StoryViewersPage extends StoryStats {
  items: StoryViewerEntry[];
  nextCursor: string | null;
}

// Résultat d'une passe de maintenance.
export interface StoryMaintenanceReport {
  expired: number;
  purged: number;
  requeued: number;
}

// Service applicatif du module stories (ADR-051, ADR-003).
// - Publication par le même envoi multipart que les vidéos (ADR-007) : brut d'une vidéo dans le bucket des uploads, puis
//   transcodage par le worker (file `story-transcode`) ; photo directement dans le bucket public des médias, vérifiée à
//   la confirmation (JPEG 9:16) et publiée aussitôt.
// - Visible 24 h après la publication : un job différé la supprime à l'échéance, et toutes les lectures ignorent une story
//   expirée (job en retard ou perdu). La maintenance rattrape les stories expirées et les envois jamais terminés.
// - Publique ; masquée pour les comptes suspendus, et les comptes bloqués dans un sens ou dans l'autre (ADR-029, ADR-037).
export class StoriesService {
  constructor(
    private readonly stories: StoryRepository,
    private readonly storage: StoryStorage,
    private readonly transcoding: StoryTranscodingQueue,
    private readonly lifecycle: StoryLifecycleQueue,
    private readonly events: StoryEventPublisher,
    private readonly users: UsersService,
    private readonly interactions: InteractionsService,
    private readonly rateLimiter: RateLimiter,
    private readonly now: () => Date = () => new Date(),
    private readonly makeId: () => string = () => newStoryId(),
  ) {}

  // ─── Publication ───────────────────────────────────────────────────────────

  // Démarre un envoi : crée la story en `uploading` et renvoie une URL signée par partie.
  async createUpload(userId: string, input: CreateStoryUploadInput): Promise<StoryUpload> {
    if (!isSupportedStoryType(input.contentType)) throw new UnsupportedStoryTypeError(input.contentType);
    const mediaType = mediaTypeOf(input.contentType);
    if (input.fileSize > maxStorySize(mediaType)) throw new StoryTooLargeError(mediaType === 'photo');
    if ((await this.stories.countActiveOrPending(userId, this.now())) >= MAX_ACTIVE_STORIES) throw new TooManyActiveStoriesError();
    // Limites de débit (ADR-039), après les contrôles de la requête. Une story vidéo compte dans la limite des vidéos.
    const retryAfter =
      mediaType === 'video'
        ? await this.rateLimiter.consume(uploadRateLimitKey(userId), UPLOAD_RATE_LIMITS)
        : await this.rateLimiter.consume(`story-photo:${userId}`, PHOTO_STORY_RATE_LIMITS);
    if (retryAfter !== null) throw new TooManyStoryActionsError(retryAfter, 'uploads');

    const id = this.makeId();
    const rawKey = storyRawKey(userId, id, input.contentType);
    const bucket = bucketOf(mediaType);
    const uploadId = await this.storage.startMultipartUpload(bucket, rawKey, input.contentType);
    let story: Story;
    try {
      story = await this.stories.create({ id, userId, mediaType, rawKey, uploadId, rawSize: input.fileSize });
    } catch (error) {
      await this.storage.abortMultipartUpload(bucket, rawKey, uploadId);
      throw error;
    }
    const parts = await this.storage.presignPartUrls(bucket, rawKey, uploadId, partCount(input.fileSize), UPLOAD_URL_TTL_SECONDS);
    return { story, partSize: UPLOAD_PART_SIZE_BYTES, parts, expiresAt: new Date(this.now().getTime() + UPLOAD_URL_TTL_SECONDS * 1000) };
  }

  // Confirme l'envoi : assemble les parties et vérifie l'objet (mêmes contrôles que les vidéos). Une photo est vérifiée
  // (JPEG 9:16) puis publiée ; une vidéo part au transcodage. Idempotent côté stockage (réponse perdue).
  async completeUpload(userId: string, storyId: string, parts: UploadedPart[]): Promise<Story> {
    const story = await this.stories.findById(storyId);
    if (!story || story.userId !== userId) throw new StoryNotFoundError(storyId);
    if (story.status !== 'uploading' || !story.uploadId) throw new StoryNotAwaitingUploadError(storyId);
    const bucket = bucketOf(story.mediaType);

    let size = await this.storage.getObjectSize(bucket, story.rawKey);
    if (size === null) {
      // S3 assemble n'importe quel sous-ensemble des parties listées : toutes sont exigées, une seule fois chacune.
      const expected = partCount(story.rawSize);
      const ordered = [...parts].sort((a, b) => a.partNumber - b.partNumber);
      if (ordered.length !== expected || ordered.some((part, index) => part.partNumber !== index + 1)) {
        throw new StoryUploadIncompleteError(`parties 1 à ${expected} attendues, chacune une seule fois`);
      }
      await this.storage.completeMultipartUpload(bucket, story.rawKey, story.uploadId, ordered);
      size = await this.storage.getObjectSize(bucket, story.rawKey);
    }
    if (size === null) throw new StoryUploadIncompleteError();
    if (size !== story.rawSize) {
      await this.storage.deleteObject(bucket, story.rawKey);
      await this.stories.markFailed(story.id);
      throw new StoryUploadIncompleteError(`${size} octets reçus, ${story.rawSize} déclarés`);
    }

    if (story.mediaType === 'photo') {
      const head = await this.storage.readStart(bucket, story.rawKey, STORY_PHOTO_HEADER_LENGTH);
      if (!isValidStoryPhoto(head)) {
        await this.storage.deleteObject(bucket, story.rawKey);
        await this.stories.markFailed(story.id);
        throw new InvalidStoryPhotoError();
      }
      const publishedAt = this.now();
      const published = await this.stories.publishPhoto(story.id, this.storage.mediaUrl(story.rawKey), publishedAt, expiry(publishedAt));
      if (!published) throw new StoryNotAwaitingUploadError(storyId);
      await this.scheduleExpiry(published);
      return published;
    }

    const uploaded = await this.stories.markUploaded(story.id);
    if (!uploaded) throw new StoryNotAwaitingUploadError(storyId);
    // Si la publication échoue (Redis indisponible), la story reste en `processing` : la maintenance la relancera.
    await this.transcoding.enqueue({ storyId: uploaded.id, rawKey: uploaded.rawKey });
    return uploaded;
  }

  // Résultat du transcodage publié par le worker (file `story-transcode-results`). Idempotent : un résultat en double, ou
  // pour une story qui n'est plus en `processing`, est ignoré (false). Story supprimée pendant son transcodage : les
  // fichiers publiés depuis par le worker sont nettoyés.
  async applyTranscodeResult(storyId: string, outcome: StoryTranscodeOutcome): Promise<boolean> {
    const publishedAt = this.now();
    const story = await this.stories.finishTranscoding(storyId, outcome, publishedAt, expiry(publishedAt));
    if (!story) {
      if (!(await this.stories.findById(storyId))) {
        await this.lifecycle.scheduleCleanup([{ storyId, mediaType: 'video', rawKey: null, uploadId: null }], 0);
      }
      return false;
    }
    if (story.status === 'ready') await this.scheduleExpiry(story);
    await this.events.storyProcessed(story);
    return true;
  }

  // Suppression par son auteur, quel que soit le statut.
  async deleteStory(userId: string, storyId: string): Promise<void> {
    const story = await this.stories.findById(storyId);
    if (!story || story.userId !== userId) throw new StoryNotFoundError(storyId);
    await this.remove(story);
  }

  // Retrait par un administrateur (signalement, ADR-038) : même suppression.
  async removeStory(storyId: string): Promise<void> {
    const story = await this.stories.findById(storyId);
    if (!story) throw new StoryNotFoundError(storyId);
    await this.remove(story);
  }

  // L'auteur voit ses stories quel que soit leur statut (suivi de la publication) ; les autres, une story visible.
  async getStory(storyId: string, viewerId: string | null): Promise<Story> {
    const story = await this.stories.findById(storyId);
    if (story && viewerId !== null && story.userId === viewerId) return story;
    return this.getVisibleStory(viewerId, storyId);
  }

  // ─── Lecture ───────────────────────────────────────────────────────────────

  // Stories actives d'un compte, de la plus ancienne à la plus récente. Aucune s'il est masqué au lecteur.
  async listUserStories(username: string, viewerId: string | null): Promise<UserStories> {
    const user = await this.users.getByUsername(username).catch((error: unknown) => {
      if (error instanceof UserNotFoundError) throw new StoryAuthorNotFoundError(username);
      throw error;
    });
    const hidden = await this.interactions.getHiddenAccountIds(viewerId);
    if (hidden.has(user.id)) return { user, items: [] };
    const stories = (await this.stories.findActiveByAuthors([user.id], this.now())).filter((story) => isActive(story, this.now()));
    const ids = stories.map((story) => story.id);
    if (viewerId === user.id) {
      const stats = await this.stories.countStats(ids, [...hidden]);
      return { user, items: stories.map((story) => ({ story, stats: stats.get(story.id) ?? { viewersCount: 0, likesCount: 0 } })) };
    }
    if (viewerId === null) return { user, items: stories.map((story) => ({ story })) };
    const states = await this.stories.findViewerStates(viewerId, ids);
    return {
      user,
      items: stories.map((story) => ({ story, viewer: { viewed: states.has(story.id), liked: states.get(story.id)?.liked ?? false } })),
    };
  }

  // Rangée de stories du compte connecté : la sienne, puis ses abonnements qui ont une story active ; ceux qui ont des
  // stories pas encore vues d'abord, puis du plus récent au plus ancien.
  async getTray(viewerId: string): Promise<StoryTrayEntry[]> {
    const following = await this.interactions.listVisibleFollowingIds(viewerId);
    const summaries = await this.stories.summarizeActive([viewerId, ...following], viewerId, this.now());
    const entries = summaries
      .map((summary) => ({ ...summary, hasUnseen: summary.userId !== viewerId && summary.viewedCount < summary.storiesCount }))
      .sort((a, b) => {
        if (a.userId === viewerId || b.userId === viewerId) return a.userId === viewerId ? -1 : 1;
        if (a.hasUnseen !== b.hasUnseen) return a.hasUnseen ? -1 : 1;
        return b.latestAt.getTime() - a.latestAt.getTime();
      })
      .slice(0, MAX_TRAY_ACCOUNTS);
    const users = new Map((await this.users.getByIds(entries.map((entry) => entry.userId))).map((user) => [user.id, user]));
    return entries.flatMap((entry) => {
      const user = users.get(entry.userId);
      return user ? [{ user, storiesCount: entry.storiesCount, latestAt: entry.latestAt, hasUnseen: entry.hasUnseen }] : [];
    });
  }

  // ─── Interactions ──────────────────────────────────────────────────────────

  // Vue d'une story d'un autre compte (la première date est gardée). Sa propre story n'est pas comptée ; au-delà de la
  // limite, la vue est ignorée sans erreur.
  async recordView(userId: string, storyId: string): Promise<void> {
    const story = await this.getVisibleStory(userId, storyId);
    if (story.userId === userId) return;
    if ((await this.rateLimiter.consume(`story-view:${userId}`, STORY_VIEW_RATE_LIMITS)) !== null) return;
    await this.stories.recordView(story.id, userId, this.now());
  }

  // Like (qui vaut vue) ou retrait, idempotents. Seuls les ajouts comptent dans la limite.
  async setLiked(userId: string, storyId: string, liked: boolean): Promise<void> {
    const story = await this.getVisibleStory(userId, storyId);
    if (story.userId === userId) throw new OwnStoryError();
    if (liked) {
      const retryAfter = await this.rateLimiter.consume(`story-like:${userId}`, STORY_LIKE_RATE_LIMITS);
      if (retryAfter !== null) throw new TooManyStoryActionsError(retryAfter, 'likes');
    }
    await this.stories.setLiked(story.id, userId, liked, this.now());
  }

  // Personnes qui ont vu sa story, de la plus récente à la plus ancienne, avec les chiffres. Réservé à l'auteur ; les
  // comptes qui lui sont masqués (suspendus, blocages) n'y figurent pas.
  async listViewers(userId: string, storyId: string, cursor: string | undefined, limit = DEFAULT_VIEWERS_PAGE_SIZE): Promise<StoryViewersPage> {
    const story = await this.stories.findById(storyId);
    if (!story || story.userId !== userId || !isActive(story, this.now())) throw new StoryNotFoundError(storyId);
    const after = cursor === undefined ? null : decodeViewersCursor(cursor);
    if (cursor !== undefined && after === null) throw new InvalidStoryCursorError();
    const hidden = [...(await this.interactions.getHiddenAccountIds(userId))];
    const [views, stats] = await Promise.all([
      this.stories.listViews(story.id, hidden, after, limit + 1),
      this.stories.countStats([story.id], hidden),
    ]);
    const page = views.slice(0, limit);
    const users = new Map((await this.users.getByIds(page.map((view) => view.userId))).map((user) => [user.id, user]));
    const last = page.at(-1);
    return {
      items: page.flatMap((view) => {
        const user = users.get(view.userId);
        return user ? [{ user, viewedAt: view.viewedAt, liked: view.liked }] : [];
      }),
      nextCursor: views.length > limit && last ? encodeViewersCursor(last) : null,
      ...(stats.get(story.id) ?? { viewersCount: 0, likesCount: 0 }),
    };
  }

  // ─── Pour les autres modules (ADR-003) ─────────────────────────────────────

  // Messagerie (réponse à une story), signalements : une story active, visible du lecteur (invité si null).
  async getVisibleStory(viewerId: string | null, storyId: string): Promise<ActiveStory> {
    const story = await this.stories.findById(storyId);
    if (!story || !isActive(story, this.now())) throw new StoryNotFoundError(storyId);
    if ((await this.interactions.getHiddenAccountIds(viewerId)).has(story.userId)) throw new StoryNotFoundError(storyId);
    return story;
  }

  // Messagerie : stories encore visibles du lecteur parmi `ids` ; les autres (expirées, supprimées, masquées) sont absentes.
  async getStoryPreviews(ids: string[], viewerId: string): Promise<Map<string, ActiveStory>> {
    const unique = [...new Set(ids)];
    if (unique.length === 0) return new Map();
    const [stories, hidden] = await Promise.all([this.stories.findByIds(unique), this.interactions.getHiddenAccountIds(viewerId)]);
    const now = this.now();
    return new Map(stories.filter((story) => isActive(story, now) && !hidden.has(story.userId)).map((story) => [story.id, story as ActiveStory]));
  }

  // Feed (anneau autour de l'avatar) : auteurs parmi `authorIds` qui ont une story visible, et s'il en reste à voir.
  async getStoryRings(authorIds: string[], viewerId: string | null): Promise<Map<string, { hasUnseen: boolean }>> {
    const unique = [...new Set(authorIds)];
    if (unique.length === 0) return new Map();
    const hidden = await this.interactions.getHiddenAccountIds(viewerId);
    const visible = unique.filter((id) => !hidden.has(id));
    if (visible.length === 0) return new Map();
    const summaries = await this.stories.summarizeActive(visible, viewerId, this.now());
    return new Map(
      summaries.map((summary) => [summary.userId, { hasUnseen: summary.userId !== viewerId && summary.viewedCount < summary.storiesCount }]),
    );
  }

  // Backoffice (signalements) : stories existantes parmi `ids`, quel que soit leur statut.
  getStoriesByIds(ids: string[]): Promise<Story[]> {
    const unique = [...new Set(ids)];
    return unique.length === 0 ? Promise.resolve([]) : this.stories.findByIds(unique);
  }

  // Avant la suppression d'un compte (écouteur de UsersService) : nettoyage des fichiers de toutes ses stories programmé.
  // La cascade de la base supprime ensuite les stories elles-mêmes.
  async scheduleAuthorFilesCleanup(userId: string): Promise<number> {
    const stories = await this.stories.findAllByAuthor(userId);
    if (stories.length === 0) return 0;
    await this.lifecycle.scheduleCleanup(stories.map(filesOf), STORY_CLEANUP_DELAY_MS);
    for (const story of stories) if (story.status === 'processing') await this.transcoding.cancel(story.id);
    return stories.length;
  }

  // ─── Jobs ──────────────────────────────────────────────────────────────────

  // Échéance d'une story (file `story-expiry`) : supprimée si elle est expirée. Déjà supprimée : rien à faire (son
  // nettoyage a été programmé par sa suppression). Renvoie vrai si elle a été supprimée.
  async expire(storyId: string): Promise<boolean> {
    const story = await this.stories.findById(storyId);
    if (!story?.expiresAt || story.expiresAt > this.now()) return false;
    await this.remove(story);
    return true;
  }

  // Nettoyage des fichiers (file `story-cleanup`). Si la story existe encore (sa suppression a échoué), rien n'est
  // supprimé et renvoie false. Idempotent : un fichier déjà absent n'est pas une erreur.
  async cleanupFiles(files: StoryFiles): Promise<boolean> {
    if (await this.stories.findById(files.storyId)) return false;
    if (files.rawKey) {
      const bucket = bucketOf(files.mediaType);
      if (files.uploadId) await this.storage.abortMultipartUpload(bucket, files.rawKey, files.uploadId);
      await this.storage.deleteObject(bucket, files.rawKey);
    }
    await this.storage.deleteMediaFiles(files.storyId);
    return true;
  }

  // Maintenance (toutes les 15 min) : stories expirées encore en base (job perdu), stories jamais publiées au bout de 24 h
  // (envoi abandonné, échec, traitement bloqué), transcodages sans nouvelles depuis 1 h relancés.
  async runMaintenance(): Promise<StoryMaintenanceReport> {
    const now = this.now();
    const expired = await this.stories.findExpired(now, STORY_MAINTENANCE_BATCH_SIZE);
    for (const story of expired) await this.remove(story);
    const unpublished = await this.stories.findUnpublishedCreatedBefore(
      new Date(now.getTime() - UNPUBLISHED_STORY_TTL_MS),
      STORY_MAINTENANCE_BATCH_SIZE,
    );
    for (const story of unpublished) await this.remove(story);
    const stuck = await this.stories.findStuckTranscodes(new Date(now.getTime() - STUCK_STORY_TRANSCODE_AFTER_MS), STORY_MAINTENANCE_BATCH_SIZE);
    for (const story of stuck) await this.transcoding.enqueue({ storyId: story.id, rawKey: story.rawKey });
    return { expired: expired.length, purged: unpublished.length, requeued: stuck.length };
  }

  // Suppression réelle : nettoyage des fichiers programmé d'abord (sans effet tant que la story existe), job de
  // transcodage retiré s'il attend encore, puis suppression en base (vues en cascade, signalements clos par trigger).
  private async remove(story: Story): Promise<void> {
    await this.lifecycle.scheduleCleanup([filesOf(story)], STORY_CLEANUP_DELAY_MS);
    if (story.status === 'processing') await this.transcoding.cancel(story.id);
    await this.stories.delete(story.id);
  }

  // Au mieux : si Redis est indisponible, la story reste invisible après son échéance (lectures filtrées) et la maintenance
  // la supprime.
  private async scheduleExpiry(story: Story): Promise<void> {
    if (!story.expiresAt) return;
    try {
      await this.lifecycle.scheduleExpiry(story.id, story.expiresAt);
    } catch {
      // Rattrapé par `runMaintenance`.
    }
  }
}

function bucketOf(mediaType: Story['mediaType']): StoryBucket {
  return mediaType === 'photo' ? 'media' : 'raw';
}

function expiry(publishedAt: Date): Date {
  return new Date(publishedAt.getTime() + STORY_LIFETIME_MS);
}
