import type { NewVideo, PublishedVideo, TranscodeOutcome, Video, VideoPosition } from './video';

export abstract class VideoRepository {
  abstract create(video: NewVideo): Promise<Video>;
  abstract findById(id: string): Promise<Video | null>;
  // Passe la vidéo de `uploading` à `processing` et efface l'uploadId, de façon atomique.
  // Renvoie null si la vidéo n'est plus en `uploading` (confirmation concurrente ou déjà faite).
  abstract markUploaded(id: string): Promise<Video | null>;
  abstract markFailed(id: string): Promise<void>;
  // Applique le résultat du transcodage, seulement si la vidéo est encore en `processing`.
  // Renvoie false sinon (résultat en double, vidéo supprimée entre-temps).
  abstract finishTranscoding(id: string, outcome: TranscodeOutcome): Promise<boolean>;
  // Vidéos restées en `uploading` depuis avant `createdBefore` (uploads abandonnés).
  abstract findAbandonedUploads(createdBefore: Date, limit: number): Promise<Video[]>;
  // Vidéos en `processing` sans changement depuis `updatedBefore` (job de transcodage perdu).
  abstract findStuckTranscodes(updatedBefore: Date, limit: number): Promise<Video[]>;
  abstract delete(id: string): Promise<void>;
  // Toutes les vidéos de `userId`, quel que soit leur statut (suppression du compte).
  abstract findAllByAuthor(userId: string): Promise<Video[]>;
  // Identifiants des vidéos publiées (`ready`), les plus récentes d'abord.
  abstract listPublishedIds(limit: number): Promise<string[]>;
  // Vidéos publiées parmi `ids`, dans un ordre quelconque ; les autres (supprimées, pas `ready`) sont absentes.
  abstract findPublishedByIds(ids: string[]): Promise<PublishedVideo[]>;
  // Vidéos publiées de `userId`, de la plus récente à la plus ancienne (date, puis identifiant décroissant),
  // strictement après `after` s'il est donné.
  abstract findPublishedByAuthor(userId: string, after: VideoPosition | null, limit: number): Promise<PublishedVideo[]>;
  // Vidéos de `userId` en `processing` ou `failed`, de la plus récente à la plus ancienne.
  abstract findUnpublishedByAuthor(userId: string, limit: number): Promise<Video[]>;
  // +1 partage sur une vidéo publiée ; renvoie le nouveau total, ou null si la vidéo n'est pas publiée.
  abstract incrementShares(id: string): Promise<number | null>;
}
