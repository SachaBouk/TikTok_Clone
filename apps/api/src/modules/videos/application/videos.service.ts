import { randomUUID } from 'node:crypto';
import {
  ABANDONED_UPLOAD_AFTER_MS,
  HOSTED_ASSET_WAIT_MS,
  MAINTENANCE_BATCH_SIZE,
  STUCK_HOSTED_VIDEO_AFTER_MS,
  STUCK_TRANSCODE_AFTER_MS,
} from '../domain/maintenance-rules';
import { CLEANUP_DELAY_MS, type VideoCleanupQueue, type VideoFilesCleanup } from '../domain/cleanup-queue';
import {
  extractHashtags,
  type Hashtag,
  type HashtagVideoPosition,
  normalizeHashtagName,
  normalizeHashtagPrefix,
  TRENDING_HASHTAGS,
  TRENDING_WINDOW_MS,
} from '../domain/hashtags';
import type { TranscodingJob, TranscodingQueue } from '../domain/transcoding-queue';
import type { VideoEventPublisher } from '../domain/video-events';
import {
  COVER_CONTENT_TYPE,
  coverKeyFor,
  isSupportedVideoType,
  DOWNLOAD_URL_TTL_SECONDS,
  downloadFileOf,
  DURATION_TOLERANCE_SECONDS,
  MAX_VIDEO_DURATION_SECONDS,
  type UploadMethod,
  MAX_COVER_SIZE_BYTES,
  MAX_VIDEO_SIZE_BYTES,
  PLUS_MAX_VIDEO_DURATION_SECONDS,
  PLUS_MAX_VIDEO_SIZE_BYTES,
  partCount,
  SUPPORTED_VIDEO_TYPES,
  UPLOAD_PART_SIZE_BYTES,
  UPLOAD_RATE_LIMITS,
  UPLOAD_URL_TTL_SECONDS,
  uploadRateLimitKey,
} from '../domain/upload-rules';
import {
  MAX_UNPUBLISHED_VIDEOS,
  type PublishedVideo,
  type PublishingAuthor,
  type Sound,
  type SoundQuery,
  type TranscodeOutcome,
  type Video,
  type VideoDetails,
  type VideoFilter,
  type VideoPosition,
  type VideoStatus,
  type VideoVisibility,
} from '../domain/video';
import {
  CoverTooLargeError,
  InvalidHashtagError,
  SoundNotFoundError,
  TooManyUploadsError,
  UnsupportedVideoTypeError,
  UploadIncompleteError,
  VideoNotAwaitingUploadError,
  VideoNotFoundError,
  VideoTooLargeError,
} from '../domain/video.errors';
import type { VideoRepository } from '../domain/video.repository';
import type { PresignedPart, UploadedPart, VideoStorage } from '../domain/video-storage';
import { newUuidV7 } from '../domain/video-id';
import { HOSTED_AUDIO_FILE, HOSTED_MP4_FILE, type HostedAsset, type HostedVideos } from '../../../mux/hosted-videos';
import { InMemoryHostedVideos } from '../../../mux/in-memory-hosted-videos';
import { InMemoryPlusMembers } from '../../../plus/in-memory-plus-members';
import type { PlusMembers } from '../../../plus/plus-members';
import type { RateLimiter } from '../../../rate-limit/rate-limiter';

export interface CreateUploadInput {
  contentType: string;
  fileSize: number;
  description?: string;
  // Publique par défaut (ADR-061).
  visibility?: VideoVisibility;
  // Autorisés par défaut (ADR-062).
  commentsEnabled?: boolean;
  // « Autoriser l'utilisation de mon son », autorisé par défaut, et son repris d'une autre vidéo (ADR-064).
  soundShared?: boolean;
  // « Autoriser le téléchargement » (ADR-067) : refusé, seul l'auteur télécharge la vidéo.
  downloadsEnabled?: boolean;
  soundId?: string;
  // ADR-065 : couverture à envoyer (JPEG), étiquette « Contenu généré par l'IA », lieu (nom et adresse affichée).
  cover?: { fileSize: number };
  aiGenerated?: boolean;
  location?: { name: string; address?: string | null };
}

// Téléchargement de la vidéo d'origine (ADR-067) : URL signée de lecture, valable peu de temps.
export interface VideoDownload {
  url: string;
  expiresAt: Date;
  contentType: string;
  fileName: string;
  size: number;
}

export interface VideoUpload {
  video: Video;
  // Pipeline maison : une URL signée par partie ; Mux (ADR-074) : `directUploadUrl`, envoyée par morceaux de `partSize`.
  method: UploadMethod;
  directUploadUrl: string | null;
  partSize: number;
  parts: PresignedPart[];
  expiresAt: Date;
  // URL signée d'un seul PUT pour la couverture (ADR-065), si elle a été demandée.
  coverUrl: string | null;
}

// Où relire une vidéo Mux depuis un webhook (ADR-074) : `passthrough` de l'asset, envoi direct, asset.
export interface HostedVideoRef {
  videoId: string | null;
  uploadId: string | null;
  assetId: string | null;
}

// Service applicatif du module videos (ADR-003). Upload direct via URLs signées (ADR-007) :
// l'API ne reçoit aucun octet vidéo, elle ne manipule que des métadonnées. Avec `VIDEO_PROVIDER=mux` (ADR-074), les
// nouvelles vidéos sont envoyées, encodées et lues chez Mux ; chaque vidéo garde son hébergeur.
export class VideosService {
  // Prévenus avant la suppression en base d'une vidéo (voir `onVideoRemoving`).
  private readonly removalListeners: ((videoId: string) => Promise<void>)[] = [];
  // Prévenus quand une vidéo est publiée (voir `onVideoPublished`).
  private readonly publicationListeners: ((video: Video) => Promise<void>)[] = [];

  constructor(
    private readonly videos: VideoRepository,
    private readonly storage: VideoStorage,
    private readonly transcoding: TranscodingQueue,
    private readonly events: VideoEventPublisher,
    private readonly cleanup: VideoCleanupQueue,
    private readonly rateLimiter: RateLimiter,
    private readonly now: () => Date = () => new Date(),
    // Abonnés « Plus » (ADR-073) : envois plus lourds et vidéos plus longues. Sans registre, personne n'est abonné.
    private readonly plus: PlusMembers = new InMemoryPlusMembers(),
    // Mux (ADR-074) ; par défaut, aucun envoi chez Mux.
    private readonly hosted: HostedVideos = new InMemoryHostedVideos(false),
    // Avertissements journalisés (bascule sur le pipeline maison quand Mux refuse un envoi).
    private readonly warn: (message: string) => void = () => {},
  ) {}

  // Démarre un upload : crée la vidéo en `uploading` et renvoie une URL signée par partie.
  async createUpload(userId: string, input: CreateUploadInput): Promise<VideoUpload> {
    if (!isSupportedVideoType(input.contentType)) throw new UnsupportedVideoTypeError(input.contentType);
    if (input.fileSize > MAX_VIDEO_SIZE_BYTES) {
      if (input.fileSize > PLUS_MAX_VIDEO_SIZE_BYTES || !(await this.plus.isActive(userId, this.now()))) throw new VideoTooLargeError();
    }
    if (input.cover && input.cover.fileSize > MAX_COVER_SIZE_BYTES) throw new CoverTooLargeError();
    // Son repris (ADR-064) : il doit être proposé (vidéo d'origine publique, publiée, qui le permet).
    if (input.soundId && (await this.videos.findSounds({ kind: 'ids', ids: [input.soundId] }, [], 0, 1)).length === 0) {
      throw new SoundNotFoundError(input.soundId);
    }
    // Limite de débit (ADR-039), après les contrôles de la requête : une requête invalide ne compte pas.
    const retryAfter = await this.rateLimiter.consume(uploadRateLimitKey(userId), UPLOAD_RATE_LIMITS);
    if (retryAfter !== null) throw new TooManyUploadsError(retryAfter);

    // Clé préfixée par l'auteur : permet de retrouver ses objets (suppression de compte, nettoyage). Pour une vidéo Mux,
    // seule la couverture y est écrite (`coverKeyFor`).
    const rawKey = `${userId}/${randomUUID()}.${SUPPORTED_VIDEO_TYPES[input.contentType]}`;
    const coverKey = input.cover ? coverKeyFor(rawKey) : null;
    const locationName = input.location?.name.trim() || null;
    const visibility = input.visibility ?? 'public';
    const fields = {
      userId,
      description: input.description?.trim() || null,
      rawKey,
      rawSize: input.fileSize,
      visibility,
      commentsEnabled: input.commentsEnabled ?? true,
      soundShared: input.soundShared ?? true,
      downloadsEnabled: input.downloadsEnabled ?? true,
      soundId: input.soundId ?? null,
      coverKey,
      aiGenerated: input.aiGenerated ?? false,
      locationName,
      locationAddress: locationName ? input.location?.address?.trim() || null : null,
    };
    const expiresAt = new Date(this.now().getTime() + UPLOAD_URL_TTL_SECONDS * 1000);
    const presignCover = () =>
      coverKey && input.cover
        ? this.storage.presignPut(coverKey, COVER_CONTENT_TYPE, input.cover.fileSize, UPLOAD_URL_TTL_SECONDS)
        : Promise.resolve(null);

    // Mux (ADR-074) : envoi direct ; refusé (plan gratuit plein, Mux injoignable), pipeline maison.
    const hosted = await this.startHostedUpload(visibility);
    if (hosted) {
      let video: Video;
      try {
        video = await this.videos.create({ ...fields, id: hosted.id, uploadId: null, provider: 'mux', muxUploadId: hosted.uploadId });
      } catch (error) {
        await this.hosted.cancelUpload(hosted.uploadId);
        throw error;
      }
      return {
        video,
        method: 'muxDirect',
        directUploadUrl: hosted.url,
        partSize: UPLOAD_PART_SIZE_BYTES,
        parts: [],
        expiresAt,
        coverUrl: await presignCover(),
      };
    }

    const uploadId = await this.storage.startMultipartUpload(rawKey, input.contentType);
    let video: Video;
    try {
      video = await this.videos.create({ ...fields, uploadId });
    } catch (error) {
      await this.storage.abortMultipartUpload(rawKey, uploadId);
      throw error;
    }

    const parts = await this.storage.presignPartUrls(rawKey, uploadId, partCount(input.fileSize), UPLOAD_URL_TTL_SECONDS);
    return {
      video,
      method: 's3Multipart',
      directUploadUrl: null,
      partSize: UPLOAD_PART_SIZE_BYTES,
      parts,
      expiresAt,
      coverUrl: await presignCover(),
    };
  }

  // Confirme la fin de l'upload : assemble les parties, vérifie l'objet, puis lance le transcodage.
  // Idempotent côté stockage : si l'assemblage a déjà réussi (réponse perdue, l'app réessaie), on reprend après.
  async completeUpload(userId: string, videoId: string, parts: UploadedPart[]): Promise<Video> {
    const video = await this.videos.findById(videoId);
    // La vidéo d'un autre utilisateur est traitée comme inexistante : on ne révèle pas son existence.
    if (!video || video.userId !== userId) throw new VideoNotFoundError(videoId);
    if (video.provider === 'mux') return this.playable(await this.completeHostedUpload(video));
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

    // Durée permise lue à la confirmation (ADR-073) et gardée : la relance du transcodage reprend la même.
    const maxDurationSeconds = (await this.plus.isActive(userId, this.now())) ? PLUS_MAX_VIDEO_DURATION_SECONDS : null;
    const uploaded = await this.videos.markUploaded(video.id, maxDurationSeconds);
    if (!uploaded) throw new VideoNotAwaitingUploadError(videoId);

    // Si la publication échoue (Redis indisponible), la vidéo reste en `processing` :
    // requeueStuckTranscodes la remettra dans la file.
    await this.transcoding.enqueue(transcodingJob(uploaded));
    return uploaded;
  }

  // Résultat du transcodage publié par le worker (ADR-012). Idempotent : un résultat en double,
  // ou pour une vidéo qui n'est plus en `processing`, est ignoré. Renvoie true s'il a été appliqué.
  // L'auteur est prévenu par WebSocket (ADR-008, ADR-011), une seule fois : pas pour un résultat ignoré.
  // Vidéo supprimée pendant son transcodage : le worker a pu publier des fichiers depuis, on les nettoie.
  // Vidéo publiée : ses hashtags sont extraits de sa description (ADR-049).
  async applyTranscodeResult(videoId: string, outcome: TranscodeOutcome): Promise<boolean> {
    const current = await this.videos.findById(videoId);
    const hashtags = outcome.status === 'ready' ? extractHashtags(current?.description ?? null) : [];
    if (!current || !(await this.videos.finishTranscoding(videoId, outcome, hashtags))) {
      if (!(await this.videos.findById(videoId))) await this.cleanup.schedule([{ videoId, rawKey: null, uploadId: null }], 0);
      return false;
    }
    const video = await this.videos.findById(videoId);
    if (video) await this.events.videoProcessed(this.playable(video));
    if (video?.status === 'ready') for (const listener of this.publicationListeners) await listener(video);
    return true;
  }

  // Miniature tirée de la couverture choisie d'une vidéo Mux (ADR-065, ADR-074 : job « couverture seule » du worker).
  // Vidéo supprimée entre-temps : la miniature publiée est nettoyée.
  async applyCoverThumbnail(videoId: string, thumbnailUrl: string): Promise<boolean> {
    if (await this.videos.setThumbnail(videoId, thumbnailUrl)) return true;
    await this.cleanup.schedule([{ videoId, rawKey: null, uploadId: null }], 0);
    return false;
  }

  // Webhook de Mux (ADR-074) : retrouve la vidéo et relit son état chez Mux. Faux si aucune vidéo ne correspond (une story,
  // peut-être). Asset d'une vidéo supprimée entre-temps : supprimé chez Mux.
  async syncHostedVideoByRef(ref: HostedVideoRef): Promise<boolean> {
    const video =
      (ref.videoId ? await this.videos.findById(ref.videoId) : null) ??
      (ref.uploadId ? await this.videos.findByMuxUpload(ref.uploadId) : null) ??
      (ref.assetId ? await this.videos.findByMuxAsset(ref.assetId) : null);
    if (video) {
      await this.syncHostedVideo(video.id);
      return true;
    }
    if (!ref.videoId) return false;
    if (ref.assetId) await this.hosted.deleteAsset(ref.assetId);
    return true;
  }

  // Relit chez Mux l'état d'une vidéo hébergée et l'applique (ADR-074) : webhooks (en double, dans le désordre),
  // maintenance, confirmation de l'envoi. Idempotent : les transitions ne partent que de `processing`.
  // - Envoi direct perdu, asset en erreur ou disparu : `failed`.
  // - Asset prêt : durée vérifiée (ADR-040, ADR-073 ; trop longue, asset supprimé et `failed`), identifiant de lecture
  //   accordé à la visibilité, puis publication (URLs sans jeton en base, son si sa version audio est prête).
  // - Vidéo déjà publiée : son ajouté quand sa version audio arrive après.
  async syncHostedVideo(videoId: string): Promise<void> {
    let video = await this.videos.findById(videoId);
    if (!video || video.provider !== 'mux' || !video.muxUploadId) return;
    if (!video.muxAssetId) {
      const upload = await this.hosted.getUpload(video.muxUploadId);
      if (upload?.status !== 'assetCreated' || !upload.assetId) {
        if ((!upload || upload.status === 'failed') && video.status === 'processing') await this.applyTranscodeResult(video.id, { status: 'failed' });
        return;
      }
      video = (await this.videos.setMuxAsset(video.id, upload.assetId)) ?? video;
    }
    // Envoi pas encore confirmé par l'app : la confirmation relira l'asset.
    const assetId = video.muxAssetId;
    if (!assetId || (video.status !== 'processing' && video.status !== 'ready')) return;
    const asset = await this.hosted.getAsset(assetId);
    if (!asset || asset.status === 'errored') {
      if (video.status === 'processing') await this.applyTranscodeResult(video.id, { status: 'failed' });
      return;
    }
    if (asset.status !== 'ready') return;
    if (video.status === 'processing') {
      const maxSeconds = video.maxDurationSeconds ?? MAX_VIDEO_DURATION_SECONDS;
      if (asset.durationSeconds !== null && asset.durationSeconds > maxSeconds + DURATION_TOLERANCE_SECONDS) {
        this.warn(`Vidéo ${video.id} trop longue chez Mux (${asset.durationSeconds} s) : échec`);
        if (await this.applyTranscodeResult(video.id, { status: 'failed' })) await this.hosted.deleteAsset(assetId);
        return;
      }
    }
    video = await this.ensurePlayback(video, assetId, asset);
    const playbackId = video.muxPlaybackId;
    if (!playbackId) return;
    const audio = asset.renditions.find((rendition) => rendition.name === HOSTED_AUDIO_FILE && rendition.status === 'ready');
    const sound =
      audio && asset.durationSeconds
        ? { audioUrl: this.hosted.fileUrl(playbackId, HOSTED_AUDIO_FILE, false), durationMs: Math.round(asset.durationSeconds * 1000) }
        : undefined;
    if (video.status === 'processing') {
      await this.applyTranscodeResult(video.id, {
        status: 'ready',
        hlsUrl: this.hosted.streamUrl(playbackId, false),
        // Couverture choisie déjà traitée par le worker : elle reste la miniature.
        thumbnailUrl: video.thumbnailUrl ?? this.hosted.thumbnailUrl(playbackId, false),
        ...(sound ? { sound } : {}),
      });
    } else if (sound) {
      await this.videos.addSound(video.id, sound.audioUrl, sound.durationMs);
    }
  }

  // Maintenance (ADR-074) : relit chez Mux les vidéos restées en `processing` (webhook perdu, tunnel coupé).
  async syncStuckHostedVideos(): Promise<number> {
    const cutoff = new Date(this.now().getTime() - STUCK_HOSTED_VIDEO_AFTER_MS);
    const stuck = await this.videos.findStuckTranscodes(cutoff, MAINTENANCE_BATCH_SIZE, 'mux');
    for (const video of stuck) await this.syncHostedVideo(video.id);
    return stuck.length;
  }

  // Suppression d'une vidéo par son auteur, quel que soit son statut. La base supprime en cascade likes,
  // favoris, republications, commentaires et notifications (retirées juste avant, voir `onVideoRemoving`) ; les messages qui la partageaient la montrent
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
    if (job.muxUploadId || job.muxAssetId) await this.discardHosted(job.muxUploadId ?? null, job.muxAssetId ?? null);
    if (job.rawKey) {
      if (job.uploadId) await this.storage.abortMultipartUpload(job.rawKey, job.uploadId);
      await this.storage.deleteObject(job.rawKey);
    }
    if (job.coverKey) await this.storage.deleteObject(job.coverKey);
    await this.storage.deleteHlsFiles(job.videoId);
    return true;
  }

  // Maintenance : supprime les uploads jamais confirmés (ADR-007, conséquence négative).
  async purgeAbandonedUploads(): Promise<number> {
    const cutoff = new Date(this.now().getTime() - ABANDONED_UPLOAD_AFTER_MS);
    const abandoned = await this.videos.findAbandonedUploads(cutoff, MAINTENANCE_BATCH_SIZE);
    for (const video of abandoned) {
      // Annule l'upload multipart : le stockage libère les parties déjà reçues. Mux : envoi annulé, asset supprimé.
      if (video.uploadId) await this.storage.abortMultipartUpload(video.rawKey, video.uploadId);
      if (video.muxUploadId) await this.discardHosted(video.muxUploadId, video.muxAssetId);
      // Couverture déjà envoyée (ADR-065) : sans effet si elle ne l'a pas été.
      if (video.coverKey) await this.storage.deleteObject(video.coverKey);
      await this.videos.delete(video.id);
    }
    return abandoned.length;
  }

  // Maintenance : remet dans la file les vidéos bloquées en `processing` (job perdu, par exemple
  // si Redis était indisponible juste après la confirmation). Sans effet si le job existe encore.
  async requeueStuckTranscodes(): Promise<number> {
    const cutoff = new Date(this.now().getTime() - STUCK_TRANSCODE_AFTER_MS);
    const stuck = await this.videos.findStuckTranscodes(cutoff, MAINTENANCE_BATCH_SIZE, 'local');
    for (const video of stuck) await this.transcoding.enqueue(transcodingJob(video));
    return stuck.length;
  }

  // Pour le module feed (ADR-003 : accès aux vidéos par ce service uniquement).
  listPublishedVideoIds(limit: number): Promise<string[]> {
    return this.videos.listPublishedIds(limit);
  }

  // Vidéos publiées parmi `ids`, dans un ordre quelconque ; celles qui ne sont plus publiées sont absentes. Une vidéo
  // privée (ADR-061) n'est rendue qu'à son auteur : `viewerId` est le compte pour qui on lit (compte connecté,
  // destinataire d'une notification, expéditeur d'un message…), null pour un invité.
  async getPublishedVideos(ids: string[], viewerId: string | null): Promise<PublishedVideo[]> {
    return (await this.videos.findPublishedByIds(ids))
      .filter((video) => video.visibility === 'public' || video.userId === viewerId)
      .map((video) => this.playable(video));
  }

  // Vidéos publiées parmi `ids`, privées comprises : backoffice (ADR-004), ou lecteur propre à chaque vidéo
  // (notifications), filtré par l'appelant.
  async getPublishedVideosIncludingPrivate(ids: string[]): Promise<PublishedVideo[]> {
    return (await this.videos.findPublishedByIds(ids)).map((video) => this.playable(video));
  }

  // Pour le module feed : vidéos publiées d'un auteur, de la plus récente à la plus ancienne. Publiques : grille
  // « Vidéos » du profil ; privées : grille « cadenas » de son auteur (ADR-061).
  async listPublishedByAuthor(
    userId: string,
    after: VideoPosition | null,
    limit: number,
    visibility: VideoVisibility = 'public',
  ): Promise<PublishedVideo[]> {
    return (await this.videos.findPublishedByAuthors([userId], after, limit, visibility)).map((video) => this.playable(video));
  }

  // Pour le module feed : vidéos publiques de plusieurs auteurs (feeds des abonnements et des amis), même ordre.
  async listPublishedByAuthors(userIds: string[], after: VideoPosition | null, limit: number): Promise<PublishedVideo[]> {
    return (await this.videos.findPublishedByAuthors(userIds, after, limit, 'public')).map((video) => this.playable(video));
  }

  // Vidéo privée ou publique (ADR-061), par son auteur seulement (404 sinon), quel que soit son statut. Les hashtags
  // suivent : retirés d'une vidéo privée, réécrits d'une vidéo redevenue publique.
  async setVisibility(userId: string, videoId: string, visibility: VideoVisibility): Promise<Video> {
    const video = await this.videos.findById(videoId);
    if (!video || video.userId !== userId) throw new VideoNotFoundError(videoId);
    const updated =
      video.visibility === visibility ? video : await this.videos.setVisibility(videoId, visibility, extractHashtags(video.description));
    if (!updated) throw new VideoNotFoundError(videoId);
    // Vidéo Mux (ADR-074) : identifiant de lecture remplacé (signé pour une vidéo privée), l'ancien lien cesse de marcher.
    // Aussi quand la visibilité n'a pas changé, pour rattraper un remplacement qui avait échoué.
    if (updated.provider === 'mux' && updated.muxAssetId) {
      const asset = await this.hosted.getAsset(updated.muxAssetId);
      if (asset) return this.playable(await this.ensurePlayback(updated, updated.muxAssetId, asset));
    }
    return this.playable(updated);
  }

  // Commentaires autorisés ou coupés (ADR-062), par son auteur seulement (404 sinon), quel que soit son statut.
  async setCommentsEnabled(userId: string, videoId: string, enabled: boolean): Promise<Video> {
    const video = await this.videos.findById(videoId);
    if (!video || video.userId !== userId) throw new VideoNotFoundError(videoId);
    if (video.commentsEnabled === enabled) return this.playable(video);
    const updated = await this.videos.setCommentsEnabled(videoId, enabled);
    if (!updated) throw new VideoNotFoundError(videoId);
    return this.playable(updated);
  }

  // « Autoriser l'utilisation de mon son » (ADR-064), par l'auteur, quel que soit le statut. Refusé, le son n'est plus
  // proposé aux autres ; les vidéos qui l'ont déjà repris le gardent.
  async setSoundShared(userId: string, videoId: string, shared: boolean): Promise<Video> {
    const video = await this.videos.findById(videoId);
    if (!video || video.userId !== userId) throw new VideoNotFoundError(videoId);
    if (video.soundShared === shared) return this.playable(video);
    const updated = await this.videos.setSoundShared(videoId, shared);
    if (!updated) throw new VideoNotFoundError(videoId);
    return this.playable(updated);
  }

  // « Autoriser le téléchargement » (ADR-067), par l'auteur, quel que soit le statut.
  async setDownloadsEnabled(userId: string, videoId: string, enabled: boolean): Promise<Video> {
    const video = await this.videos.findById(videoId);
    if (!video || video.userId !== userId) throw new VideoNotFoundError(videoId);
    if (video.downloadsEnabled === enabled) return this.playable(video);
    const updated = await this.videos.setDownloadsEnabled(videoId, enabled);
    if (!updated) throw new VideoNotFoundError(videoId);
    return this.playable(updated);
  }

  // URL signée du fichier d'origine d'une vidéo publiée (ADR-067). Les droits (visibilité, comptes masqués, réglage
  // de l'auteur) sont vérifiés par `interactions`, qui l'appelle ; un brut disparu donne 404.
  async presignDownload(videoId: string): Promise<VideoDownload> {
    const video = await this.videos.findById(videoId);
    if (!video || video.status !== 'ready') throw new VideoNotFoundError(videoId);
    const expiresAt = new Date(this.now().getTime() + DOWNLOAD_URL_TTL_SECONDS * 1000);
    // Vidéo Mux (ADR-074) : version MP4 encodée par Mux (pas le fichier d'origine), signée pour une vidéo privée. Pas
    // encore prête : comme une vidéo indisponible.
    if (video.provider === 'mux') {
      const asset = video.muxAssetId && video.muxPlaybackId ? await this.hosted.getAsset(video.muxAssetId) : null;
      const mp4 = asset?.renditions.find((rendition) => rendition.name === HOSTED_MP4_FILE && rendition.status === 'ready');
      if (!mp4 || !video.muxPlaybackId) throw new VideoNotFoundError(videoId);
      const url = this.hosted.fileUrl(video.muxPlaybackId, HOSTED_MP4_FILE, video.muxSigned);
      return { url, expiresAt, contentType: 'video/mp4', fileName: `${videoId}.mp4`, size: mp4.size ?? 0 };
    }
    const size = await this.storage.getObjectSize(video.rawKey);
    if (size === null) throw new VideoNotFoundError(videoId);
    const { contentType, fileName } = downloadFileOf(video.rawKey, videoId);
    const url = await this.storage.presignGet(video.rawKey, fileName, DOWNLOAD_URL_TTL_SECONDS);
    return { url, expiresAt, contentType, fileName, size };
  }

  // Sons proposés (ADR-064, module feed) : auteurs masqués exclus, page à partir de `offset`.
  listSounds(query: SoundQuery, excludedAuthorIds: string[], offset: number, limit: number): Promise<Sound[]> {
    if (query.kind === 'ids' && query.ids.length === 0) return Promise.resolve([]);
    return this.videos.findSounds(query, [...new Set(excludedAuthorIds)], offset, limit);
  }

  // Favori ajouté ou retiré ; un son qui n'est plus proposé ne peut qu'être retiré.
  async setSoundFavorite(userId: string, soundId: string, active: boolean, excludedAuthorIds: string[]): Promise<void> {
    if (active && (await this.listSounds({ kind: 'ids', ids: [soundId] }, excludedAuthorIds, 0, 1)).length === 0) {
      throw new SoundNotFoundError(soundId);
    }
    await this.videos.setSoundFavorite(userId, soundId, active);
  }

  favoritedSoundIds(userId: string, soundIds: string[]): Promise<Set<string>> {
    if (soundIds.length === 0) return Promise.resolve(new Set());
    return this.videos.findFavoritedSoundIds(userId, [...new Set(soundIds)]);
  }

  // Vidéos de l'auteur pas encore publiées (en traitement) ou en échec, visibles de lui seul, en tête de sa grille.
  // Les envois en cours (`uploading`) n'y figurent pas : l'app les suit elle-même.
  async listUnpublishedVideos(userId: string): Promise<Video[]> {
    return (await this.videos.findUnpublishedByAuthor(userId, MAX_UNPUBLISHED_VIDEOS)).map((video) => this.playable(video));
  }

  // Partage d'une vidéo publiée (module interactions). Pas de table de partages (ADR-006) : seul le
  // compteur existe, écrit ici puisqu'il appartient à la table `videos`. Null si la vidéo n'est pas publiée.
  recordShare(videoId: string): Promise<number | null> {
    return this.videos.incrementShares(videoId);
  }

  // Backoffice (ADR-004) : vidéos de tous statuts, filtrées, de la plus récente à la plus ancienne,
  // strictement avant `beforeId` s'il est donné.
  async listVideoDetails(filter: VideoFilter, beforeId: string | null, limit: number): Promise<VideoDetails[]> {
    return (await this.videos.findDetails(filter, beforeId, limit)).map((video) => this.playable(video));
  }

  // Backoffice : vidéos existantes parmi `ids` (tous statuts), dans un ordre quelconque.
  async getVideoDetails(ids: string[]): Promise<VideoDetails[]> {
    return (await this.videos.findDetailsByIds([...new Set(ids)])).map((video) => this.playable(video));
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

  // Pour le module interactions (comptes suggérés, ADR-068) : comptes qui publient des vidéos publiques, hors
  // `excludedIds`, du plus grand nombre de vidéos au plus petit.
  listPublishingAuthors(excludedIds: string[], limit: number): Promise<PublishingAuthor[]> {
    return this.videos.findPublishingAuthors([...new Set(excludedIds)], limit);
  }

  // Pour le module users : likes reçus par un compte, sur ses vidéos publiées (compteur « J'aime » du profil, ADR-056).
  countLikesReceived(userId: string): Promise<number> {
    return this.videos.sumLikesByAuthor(userId);
  }

  // Hashtags (ADR-049). Pour le module search : hashtags qui commencent par `prefix` (« # » initial ignoré), ayant au
  // moins une vidéo, du plus utilisé au moins utilisé. Début de nom invalide : aucun.
  searchHashtags(prefix: string, limit: number): Promise<Hashtag[]> {
    const normalized = normalizeHashtagPrefix(prefix);
    return normalized ? this.videos.searchHashtags(normalized, limit) : Promise.resolve([]);
  }

  // Hashtags tendance : vidéos publiées ces 7 derniers jours, puis nombre total de vidéos.
  trendingHashtags(): Promise<Hashtag[]> {
    return this.videos.findTrendingHashtags(new Date(this.now().getTime() - TRENDING_WINDOW_MS), TRENDING_HASHTAGS);
  }

  // Un hashtag et son nombre de vidéos ; un nom valide inconnu en a 0. Lève InvalidHashtagError.
  async getHashtag(name: string): Promise<Hashtag> {
    const normalized = this.hashtagName(name);
    return (await this.videos.findHashtag(normalized)) ?? { name: normalized, videosCount: 0 };
  }

  // Pour le module feed : vidéos publiées d'un hashtag, de la plus récente à la plus ancienne. Lève InvalidHashtagError.
  async listHashtagVideos(name: string, after: HashtagVideoPosition | null, limit: number): Promise<HashtagVideoPosition[]> {
    return this.videos.listHashtagVideos(this.hashtagName(name), after, limit);
  }

  // Un autre module agit juste avant la suppression en base d'une vidéo, par son auteur ou un administrateur (ex.
  // notifications : retirer et annoncer les siennes, ADR-043). Le module videos ne dépend ainsi pas de lui. Un échec de
  // l'écouteur fait échouer la suppression.
  onVideoRemoving(listener: (videoId: string) => Promise<void>): void {
    this.removalListeners.push(listener);
  }

  // Un autre module agit quand une vidéo est publiée (passage en `ready`), une seule fois par vidéo (ex. interactions :
  // prévenir les comptes mentionnés dans sa description, ADR-065). Un échec de l'écouteur fait rejouer le résultat du
  // transcodage, qui est alors ignoré : l'écouteur doit gérer ses propres erreurs.
  onVideoPublished(listener: (video: Video) => Promise<void>): void {
    this.publicationListeners.push(listener);
  }

  // Une vidéo pas encore `ready` n'est visible que par son auteur (suivi du traitement), une vidéo privée aussi (ADR-061 ;
  // une vidéo Mux privée porte une URL signée, ADR-074).
  async getVideo(videoId: string, viewerId: string | null): Promise<Video> {
    const video = await this.videos.findById(videoId);
    if (!video || ((video.status !== 'ready' || video.visibility === 'private') && video.userId !== viewerId)) {
      throw new VideoNotFoundError(videoId);
    }
    return this.playable(video);
  }

  // URLs d'une vidéo Mux privée (ADR-074) : celles de la base n'ont pas de jeton ; on l'ajoute à chaque lecture (jeton de
  // 6 à 12 h, identique dans une même fenêtre). La miniature n'en reçoit un que si c'est celle de Mux (pas la couverture).
  private playable<T extends { hlsUrl: string | null; thumbnailUrl: string | null; muxPlaybackId?: string | null; muxSigned?: boolean }>(
    video: T,
  ): T {
    const playbackId = video.muxPlaybackId;
    if (!video.muxSigned || !playbackId) return video;
    return {
      ...video,
      hlsUrl: video.hlsUrl ? this.hosted.streamUrl(playbackId, true) : video.hlsUrl,
      thumbnailUrl:
        video.thumbnailUrl === this.hosted.thumbnailUrl(playbackId, false) ? this.hosted.thumbnailUrl(playbackId, true) : video.thumbnailUrl,
    };
  }

  // Envoi direct chez Mux (ADR-074), si `VIDEO_PROVIDER=mux`. Refusé (plan gratuit plein, Mux injoignable) : null, et
  // l'envoi passe par le pipeline maison.
  private async startHostedUpload(visibility: VideoVisibility): Promise<{ id: string; uploadId: string; url: string } | null> {
    if (!this.hosted.uploadsEnabled) return null;
    const id = newUuidV7(this.now().getTime());
    try {
      const upload = await this.hosted.createUpload({
        passthrough: `video:${id}`,
        policy: visibility === 'private' ? 'signed' : 'public',
        staticRenditions: true,
        timeoutSeconds: UPLOAD_URL_TTL_SECONDS,
      });
      return { id, ...upload };
    } catch (error) {
      this.warn(`Mux a refusé l'envoi (${(error as Error).message}) : pipeline maison`);
      return null;
    }
  }

  // Confirmation d'un envoi direct chez Mux : l'asset doit exister (fichier entièrement reçu). Puis `processing`, job de la
  // couverture choisie (ADR-065), et lecture de l'asset (déjà prêt pour une petite vidéo, webhook passé avant).
  private async completeHostedUpload(video: Video): Promise<Video> {
    if (video.status !== 'uploading' || !video.muxUploadId) throw new VideoNotAwaitingUploadError(video.id);
    let state = await this.hosted.getUpload(video.muxUploadId);
    // Mux crée l'asset juste après le dernier morceau : quelques instants d'attente au plus.
    for (const delay of HOSTED_ASSET_WAIT_MS) {
      if (state?.status !== 'waiting') break;
      await new Promise((resolve) => setTimeout(resolve, delay));
      state = await this.hosted.getUpload(video.muxUploadId);
    }
    if (!state || state.status === 'failed') {
      await this.videos.markFailed(video.id);
      throw new UploadIncompleteError('envoi refusé ou expiré chez Mux');
    }
    if (state.status !== 'assetCreated' || !state.assetId) throw new UploadIncompleteError('fichier pas encore reçu par Mux');
    await this.videos.setMuxAsset(video.id, state.assetId);

    const maxDurationSeconds = (await this.plus.isActive(video.userId, this.now())) ? PLUS_MAX_VIDEO_DURATION_SECONDS : null;
    const uploaded = await this.videos.markUploaded(video.id, maxDurationSeconds);
    if (!uploaded) throw new VideoNotAwaitingUploadError(video.id);
    if (uploaded.coverKey)
      await this.transcoding.enqueue({ videoId: uploaded.id, rawKey: uploaded.rawKey, coverKey: uploaded.coverKey, coverOnly: true });
    await this.syncHostedVideo(uploaded.id);
    return (await this.videos.findById(uploaded.id)) ?? uploaded;
  }

  // Identifiant de lecture accordé à la visibilité (signé pour une vidéo privée, ADR-061) : celui de l'asset s'il existe,
  // sinon un nouveau ; les autres sont supprimés après coup (un lien copié avant cesse de marcher). Vidéo publiée : ses URLs
  // (et celle de son son) suivent, la couverture choisie reste la miniature.
  private async ensurePlayback(video: Video, assetId: string, asset: HostedAsset): Promise<Video> {
    const policy = video.visibility === 'private' ? 'signed' : 'public';
    const playbackId = asset.playbackIds.find((entry) => entry.policy === policy)?.id ?? (await this.hosted.addPlaybackId(assetId, policy));
    let current = video;
    if (playbackId !== video.muxPlaybackId || video.muxSigned !== (policy === 'signed')) {
      const muxThumbnail = video.muxPlaybackId ? this.hosted.thumbnailUrl(video.muxPlaybackId, false) : null;
      const urls =
        video.status === 'ready'
          ? {
              hlsUrl: this.hosted.streamUrl(playbackId, false),
              thumbnailUrl: !video.thumbnailUrl || video.thumbnailUrl === muxThumbnail ? this.hosted.thumbnailUrl(playbackId, false) : null,
              audioUrl: this.hosted.fileUrl(playbackId, HOSTED_AUDIO_FILE, false),
            }
          : null;
      current = (await this.videos.setMuxPlayback(video.id, playbackId, policy === 'signed', urls)) ?? video;
    }
    for (const other of asset.playbackIds) if (other.id !== playbackId) await this.hosted.deletePlaybackId(assetId, other.id);
    return current;
  }

  // Envoi direct annulé, ou asset supprimé s'il a été créé (vidéo supprimée, envoi abandonné).
  private async discardHosted(uploadId: string | null, assetId: string | null): Promise<void> {
    const asset = assetId ?? (uploadId ? ((await this.hosted.getUpload(uploadId))?.assetId ?? null) : null);
    if (asset) await this.hosted.deleteAsset(asset);
    else if (uploadId) await this.hosted.cancelUpload(uploadId);
  }

  private hashtagName(name: string): string {
    const normalized = normalizeHashtagName(name);
    if (!normalized) throw new InvalidHashtagError(name);
    return normalized;
  }

  // Suppression réelle : nettoyage des fichiers programmé d'abord (sans effet tant que la vidéo existe),
  // job de transcodage retiré s'il attend encore, autres modules prévenus, puis suppression en base (cascade).
  private async remove(video: Video): Promise<void> {
    await this.cleanup.schedule([filesOf(video)], CLEANUP_DELAY_MS);
    if (video.status === 'processing') await this.transcoding.cancel(video.id);
    for (const listener of this.removalListeners) await listener(video.id);
    await this.videos.delete(video.id);
  }
}

function filesOf(video: Video): VideoFilesCleanup {
  return {
    videoId: video.id,
    rawKey: video.rawKey,
    uploadId: video.uploadId,
    ...(video.coverKey ? { coverKey: video.coverKey } : {}),
    ...(video.muxUploadId ? { muxUploadId: video.muxUploadId, muxAssetId: video.muxAssetId } : {}),
  };
}

// Job de transcodage : la couverture choisie (ADR-065) devient la miniature ; durée permise d'un abonné (ADR-073).
function transcodingJob(video: Video): TranscodingJob {
  return {
    videoId: video.id,
    rawKey: video.rawKey,
    ...(video.coverKey ? { coverKey: video.coverKey } : {}),
    ...(video.maxDurationSeconds ? { maxDurationSeconds: video.maxDurationSeconds } : {}),
  };
}
