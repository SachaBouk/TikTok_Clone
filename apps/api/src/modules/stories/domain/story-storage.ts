import type { PresignedPart, UploadedPart } from '../../videos/domain/video-storage';

export type { PresignedPart, UploadedPart };

// Où vit un objet de story : brut d'une vidéo (bucket des uploads, privé) ou photo (bucket public des médias, le CDN en
// production, sous `<storyId>/`).
export type StoryBucket = 'raw' | 'media';

// Port du stockage objet des stories (compatible S3, ADR-015). Même envoi multipart que les vidéos (ADR-007).
export abstract class StoryStorage {
  abstract startMultipartUpload(bucket: StoryBucket, key: string, contentType: string): Promise<string>;
  abstract presignPartUrls(bucket: StoryBucket, key: string, uploadId: string, partCount: number, expiresInSeconds: number): Promise<PresignedPart[]>;
  // Lève StoryUploadIncompleteError si des parties manquent ou si un ETag ne correspond pas.
  abstract completeMultipartUpload(bucket: StoryBucket, key: string, uploadId: string, parts: UploadedPart[]): Promise<void>;
  abstract abortMultipartUpload(bucket: StoryBucket, key: string, uploadId: string): Promise<void>;
  // Taille de l'objet en octets, ou null s'il n'existe pas.
  abstract getObjectSize(bucket: StoryBucket, key: string): Promise<number | null>;
  // Premiers octets d'un objet (en-tête d'une photo).
  abstract readStart(bucket: StoryBucket, key: string, length: number): Promise<Uint8Array>;
  abstract deleteObject(bucket: StoryBucket, key: string): Promise<void>;
  // Tous les fichiers publiés d'une story (photo, ou HLS et miniature), sous `<storyId>/` du bucket des médias.
  abstract deleteMediaFiles(storyId: string): Promise<void>;
  // URL publique d'un objet du bucket des médias (CDN en production).
  abstract mediaUrl(key: string): string;
}
