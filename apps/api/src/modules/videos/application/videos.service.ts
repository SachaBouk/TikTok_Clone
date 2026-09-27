import { randomUUID } from 'node:crypto';
import { ABANDONED_UPLOAD_AFTER_MS, MAINTENANCE_BATCH_SIZE, STUCK_TRANSCODE_AFTER_MS } from '../domain/maintenance-rules';
import { CLEANUP_DELAY_MS, type VideoCleanupQueue, type VideoFilesCleanup } from '../domain/cleanup-queue';
import type { TranscodingQueue } from '../domain/transcoding-queue';
import type { VideoEventPublisher } from '../domain/video-events';
import {
  isSupportedVideoType,
  MAX_VIDEO_SIZE_BYTES,
  partCount,
  SUPPORTED_VIDEO_TYPES,
  UPLOAD_PART_SIZE_BYTES,
  UPLOAD_URL_TTL_SECONDS,
} from '../domain/upload-rules';
import {
  MAX_UNPUBLISHED_VIDEOS,
  type PublishedVideo,
  type TranscodeOutcome,
  type Video,
  type VideoDetails,
  type VideoFilter,
  type VideoPosition,
  type VideoStatus,
} from '../domain/video';
import {
  UnsupportedVideoTypeError,
  UploadIncompleteError,
  VideoNotAwaitingUploadError,
  VideoNotFoundError,
  VideoTooLargeError,
} from '../domain/video.errors';
import type { VideoRepository } from '../domain/video.repository';
import type { PresignedPart, UploadedPart, VideoStorage } from '../domain/video-storage';

export interface CreateUploadInput {
  contentType: string;
  fileSize: number;
  description?: string;
}

export interface VideoUpload {
  video: Video;
  partSize: number;
  parts: PresignedPart[];
  expiresAt: Date;
}

// Service applicatif du module videos (ADR-003). Upload direct via URLs signées (ADR-007) :
// l'API ne reçoit aucun octet vidéo, elle ne manipule que des métadonnées.
export class VideosService {
  constructor(
    private readonly videos: VideoRepository,
    private readonly storage: VideoStorage,
    private readonly transcoding: TranscodingQueue,
    private readonly events: VideoEventPublisher,
    private readonly cleanup: VideoCleanupQueue,
    private readonly now: () => Date = () => new Date(),
  ) {}

  // Démarre un upload : crée la vidéo en `uploading` et renvoie une URL signée par partie.
  async createUpload(userId: string, input: CreateUploadInput): Promise<VideoUpload> {
    if (!isSupportedVideoType(input.contentType)) throw new UnsupportedVideoTypeError(input.contentType);
    if (input.fileSize > MAX_VIDEO_SIZE_BYTES) throw new VideoTooLargeError();

    // Clé préfixée par l'auteur : permet de retrouver ses objets (suppression de compte, nettoyage).
    const rawKey = `${userId}/${randomUUID()}.${SUPPORTED_VIDEO_TYPES[input.contentType]}`;
    const uploadId = await this.storage.startMultipartUpload(rawKey, input.contentType);

    let video: Video;
    try {
      video = await this.videos.create({
        userId,
        description: input.description?.trim() || null,
        rawKey,
        uploadId,
        rawSize: input.fileSize,
      });
    } catch (error) {
      await this.storage.abortMultipartUpload(rawKey, uploadId);
      throw error;
    }

    const parts = await this.storage.presignPartUrls(rawKey, uploadId, partCount(input.fileSize), UPLOAD_URL_TTL_SECONDS);
    return {
      video,
      partSize: UPLOAD_PART_SIZE_BYTES,
      parts,
      expiresAt: new Date(this.now().getTime() + UPLOAD_URL_TTL_SECONDS * 1000),
    };
  }

  // Confirme la fin de l'upload : assemble les parties, vérifie l'objet, puis lance le transcodage.
  // Idempotent côté stockage : si l'assemblage a déjà réussi (réponse perdue, l'app réessaie), on reprend après.
  async completeUpload(userId: string, videoId: string, parts: UploadedPart[]): Promise<Video> {
    const video = await this.videos.findById(videoId);
    // La vidéo d'un autre utilisateur est traitée comme inexistante : on ne révèle pas son existence.
    if (!video || video.userId !== userId) throw new VideoNotFoundError(videoId);
    if (video.status !== 'uploading' || !video.uploadId) throw new VideoNotAwaitingUploadError(videoId);

    let size = await this.storage.getObjectSize(video.rawKey);
    if (size === null) {
      // S3 assemble n'importe quel sous-ensemble des parties listées : sans ce contrôle,
      // une confirmation qui omet des parties produirait une vidéo tronquée.
      const expected = partCount(video.rawSize);
      const ordered = [...parts].sort((a, b) => a.partNumber - b.partNumber);
      if (ordered.length !== expected || ordered.some((part, index) => part.partNumber !== index + 1)) {
        throw new UploadIncompleteError(`parties 1 à ${expected} attendues, chacune une seule fois`);
      }
      await this.storage.completeMultipartUpload(video.rawKey, video.uploadId, ordered);
      size = await this.storage.getObjectSize(video.rawKey);
    }
    if (size === null) throw new UploadIncompleteError();

    // Les URLs signées ne bornent pas la taille des parties : l'objet final doit avoir exactement
    // la taille déclarée (donc sous la limite). Sinon l'upload est perdu : il faut recommencer.
    if (size !== video.rawSize) {
      await this.storage.deleteObject(video.rawKey);
      await this.videos.markFailed(video.id);
      throw new UploadIncompleteError(`${size} octets reçus, ${video.rawSize} déclarés`);
    }

    const uploaded = await this.videos.markUploaded(video.id);
    if (!uploaded) throw new VideoNotAwaitingUploadError(videoId);

    // Si la publication échoue (Redis indisponible), la vidéo reste en `processing` :
    // requeueStuckTranscodes la remettra dans la file.
    await this.transcoding.enqueue({ videoId: uploaded.id, rawKey: uploaded.rawKey });
    return uploaded;
  }

  // Résultat du transcodage publié par le worker (ADR-012). Idempotent : un résultat en double,
  // ou pour une vidéo qui n'est plus en `processing`, est ignoré. Renvoie true s'il a été appliqué.
  // L'auteur est prévenu par WebSocket (ADR-008, ADR-011), une seule fois : pas pour un résultat ignoré.
  // Vidéo supprimée pendant son transcodage : le worker a pu publier des fichiers depuis, on les nettoie.
  async applyTranscodeResult(videoId: string, outcome: TranscodeOutcome): Promise<boolean> {
    if (!(await this.videos.finishTranscoding(videoId, outcome))) {
      if (!(await this.videos.findById(videoId))) await this.cleanup.schedule([{ videoId, rawKey: null, uploadId: null }], 0);
      return false;
    }
    const video = await this.videos.findById(videoId);
    if (video) await this.events.videoProcessed(video);
    return true;
  }

  // Suppression d'une vidéo par son auteur, quel que soit son statut. La base supprime en cascade likes,
  // favoris, republications, commentaires et notifications ; les messages qui la partageaient la montrent
  // indisponible. Les fichiers sont supprimés ensuite, par la file de nettoyage (voir CLEANUP_DELAY_MS).
  async deleteVideo(userId: string, videoId: string): Promise<void> {
    const video = await this.videos.findById(videoId);
    if (!video || video.userId !== userId) throw new VideoNotFoundError(videoId);
    await this.remove(video);
  }

  // Retrait d'une vidéo par un administrateur (backoffice, ADR-004) : même suppression que par son auteur,
  // quel que soit son statut. L'auteur n'est pas prévenu.
  async removeVideo(videoId: string): Promise<void> {
    const video = await this.videos.findById(videoId);
    if (!video) throw new VideoNotFoundError(videoId);
    await this.remove(video);
  }

  // Avant la suppression d'un compte (module users) : programme le nettoyage des fichiers de toutes ses
  // vidéos. La cascade de la base supprime ensuite les vidéos elles-mêmes. Renvoie le nombre de vidéos.
  async scheduleAuthorFilesCleanup(userId: string): Promise<number> {
    const videos = await this.videos.findAllByAuthor(userId);
    if (videos.length === 0) return 0;
    await this.cleanup.schedule(videos.map(filesOf), CLEANUP_DELAY_MS);
    for (const video of videos) if (video.status === 'processing') await this.transcoding.cancel(video.id);
    return videos.length;
  }

  // Exécution d'un nettoyage (file `video-cleanup`). Si la vidéo existe encore (sa suppression a échoué),
  // rien n'est supprimé et renvoie false. Idempotent : un fichier déjà absent n'est pas une erreur.
  async cleanupFiles(job: VideoFilesCleanup): Promise<boolean> {
    if (await this.videos.findById(job.videoId)) return false;
    if (job.rawKey) {
      if (job.uploadId) await this.storage.abortMultipartUpload(job.rawKey, job.uploadId);
      await this.storage.deleteObject(job.rawKey);
    }
    await this.storage.deleteHlsFiles(job.videoId);
    return true;
  }

  // Maintenance : supprime les uploads jamais confirmés (ADR-007, conséquence négative).
  async purgeAbandonedUploads(): Promise<number> {
    const cutoff = new Date(this.now().getTime() - ABANDONED_UPLOAD_AFTER_MS);
    const abandoned = await this.videos.findAbandonedUploads(cutoff, MAINTENANCE_BATCH_SIZE);
    for (const video of abandoned) {
      // Annule l'upload multipart : le stockage libère les parties déjà reçues.
      if (video.uploadId) await this.storage.abortMultipartUpload(video.rawKey, video.uploadId);
      await this.videos.delete(video.id);
    }
    return abandoned.length;
  }

  // Maintenance : remet dans la file les vidéos bloquées en `processing` (job perdu, par exemple
  // si Redis était indisponible juste après la confirmation). Sans effet si le job existe encore.
  async requeueStuckTranscodes(): Promise<number> {
    const cutoff = new Date(this.now().getTime() - STUCK_TRANSCODE_AFTER_MS);
    const stuck = await this.videos.findStuckTranscodes(cutoff, MAINTENANCE_BATCH_SIZE);
    for (const video of stuck) await this.transcoding.enqueue({ videoId: video.id, rawKey: video.rawKey });
    return stuck.length;
  }

  // Pour le module feed (ADR-003 : accès aux vidéos par ce service uniquement).
  listPublishedVideoIds(limit: number): Promise<string[]> {
    return this.videos.listPublishedIds(limit);
  }

  // Vidéos publiées parmi `ids`, dans un ordre quelconque ; celles qui ne sont plus publiées sont absentes.
  getPublishedVideos(ids: string[]): Promise<PublishedVideo[]> {
    return this.videos.findPublishedByIds(ids);
  }

  // Pour le module feed : vidéos publiées d'un auteur (grille du profil), de la plus récente à la plus ancienne.
  listPublishedByAuthor(userId: string, after: VideoPosition | null, limit: number): Promise<PublishedVideo[]> {
    return this.videos.findPublishedByAuthor(userId, after, limit);
  }

  // Vidéos de l'auteur pas encore publiées (en traitement) ou en échec, visibles de lui seul, en tête de sa grille.
  // Les envois en cours (`uploading`) n'y figurent pas : l'app les suit elle-même.
  listUnpublishedVideos(userId: string): Promise<Video[]> {
    return this.videos.findUnpublishedByAuthor(userId, MAX_UNPUBLISHED_VIDEOS);
  }

  // Partage d'une vidéo publiée (module interactions). Pas de table de partages (ADR-006) : seul le
  // compteur existe, écrit ici puisqu'il appartient à la table `videos`. Null si la vidéo n'est pas publiée.
  recordShare(videoId: string): Promise<number | null> {
    return this.videos.incrementShares(videoId);
  }

  // Backoffice (ADR-004) : vidéos de tous statuts, filtrées, de la plus récente à la plus ancienne,
  // strictement avant `beforeId` s'il est donné.
  listVideoDetails(filter: VideoFilter, beforeId: string | null, limit: number): Promise<VideoDetails[]> {
    return this.videos.findDetails(filter, beforeId, limit);
  }

  // Backoffice : vidéos existantes parmi `ids` (tous statuts), dans un ordre quelconque.
  getVideoDetails(ids: string[]): Promise<VideoDetails[]> {
    return this.videos.findDetailsByIds([...new Set(ids)]);
  }

  // Backoffice : nombre de vidéos par statut, et de vidéos créées depuis `since`.
  async countVideos(since: Date): Promise<{ byStatus: Record<VideoStatus, number>; createdSince: number }> {
    const [byStatus, createdSince] = await Promise.all([this.videos.countByStatus(), this.videos.countCreatedSince(since)]);
    return { byStatus, createdSince };
  }

  // Backoffice : nombre de vidéos (tous statuts) de chaque compte ; un compte sans vidéo est absent.
  countVideosByAuthors(userIds: string[]): Promise<Map<string, number>> {
    return this.videos.countByAuthors([...new Set(userIds)]);
  }

  // Une vidéo pas encore `ready` n'est visible que par son auteur (suivi du traitement).
  async getVideo(videoId: string, viewerId: string | null): Promise<Video> {
    const video = await this.videos.findById(videoId);
    if (!video || (video.status !== 'ready' && video.userId !== viewerId)) throw new VideoNotFoundError(videoId);
    return video;
  }

  // Suppression réelle : nettoyage des fichiers programmé d'abord (sans effet tant que la vidéo existe),
  // job de transcodage retiré s'il attend encore, puis suppression en base (cascade).
  private async remove(video: Video): Promise<void> {
    await this.cleanup.schedule([filesOf(video)], CLEANUP_DELAY_MS);
    if (video.status === 'processing') await this.transcoding.cancel(video.id);
    await this.videos.delete(video.id);
  }
}

function filesOf(video: Video): VideoFilesCleanup {
  return { videoId: video.id, rawKey: video.rawKey, uploadId: video.uploadId };
}
