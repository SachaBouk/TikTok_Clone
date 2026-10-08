import { createHash, randomUUID } from 'node:crypto';
import { StoryUploadIncompleteError } from '../domain/story.errors';
import { type PresignedPart, type StoryBucket, StoryStorage, type UploadedPart } from '../domain/story-storage';

interface PendingUpload {
  bucket: StoryBucket;
  key: string;
  parts: Map<number, { etag: string; size: number }>;
}

// Adaptateur en mémoire pour les tests : simule le multipart S3 et le contenu des objets (en-tête d'une photo).
export class InMemoryStoryStorage extends StoryStorage {
  readonly uploads = new Map<string, PendingUpload>();
  // `<bucket>:<clé>` → contenu (seule la taille compte, sauf pour l'en-tête d'une photo).
  readonly objects = new Map<string, Uint8Array>();
  // Contenu à donner au prochain objet assemblé pour une clé (photo envoyée par le test).
  readonly contents = new Map<string, Uint8Array>();
  // Fichiers publiés sous `<storyId>/` dans le bucket des médias (HLS, miniature), en plus des photos.
  readonly mediaFiles = new Set<string>();

  async startMultipartUpload(bucket: StoryBucket, key: string): Promise<string> {
    const uploadId = randomUUID();
    this.uploads.set(uploadId, { bucket, key, parts: new Map() });
    return uploadId;
  }

  async presignPartUrls(bucket: StoryBucket, key: string, uploadId: string, partCount: number): Promise<PresignedPart[]> {
    return Array.from({ length: partCount }, (_, i) => ({ partNumber: i + 1, url: `memory://${bucket}/${key}?uploadId=${uploadId}&part=${i + 1}` }));
  }

  // Ce que ferait l'app avec l'URL signée : envoie une partie et reçoit son ETag.
  putPart(uploadId: string, partNumber: number, size: number): string {
    const upload = this.uploads.get(uploadId);
    if (!upload) throw new Error(`Upload inconnu : ${uploadId}`);
    const etag = `"${createHash('md5').update(`${uploadId}:${partNumber}:${size}`).digest('hex')}"`;
    upload.parts.set(partNumber, { etag, size });
    return etag;
  }

  async completeMultipartUpload(bucket: StoryBucket, key: string, uploadId: string, parts: UploadedPart[]): Promise<void> {
    const upload = this.uploads.get(uploadId);
    if (!upload || upload.key !== key || upload.bucket !== bucket) throw new StoryUploadIncompleteError('NoSuchUpload');
    for (const part of parts) {
      if (upload.parts.get(part.partNumber)?.etag !== part.etag) throw new StoryUploadIncompleteError('InvalidPart');
    }
    const size = parts.reduce((total, part) => total + upload.parts.get(part.partNumber)!.size, 0);
    this.uploads.delete(uploadId);
    const content = this.contents.get(key) ?? new Uint8Array(0);
    const object = new Uint8Array(size);
    object.set(content.subarray(0, size));
    this.objects.set(`${bucket}:${key}`, object);
  }

  async abortMultipartUpload(_bucket: StoryBucket, _key: string, uploadId: string): Promise<void> {
    this.uploads.delete(uploadId);
  }

  async getObjectSize(bucket: StoryBucket, key: string): Promise<number | null> {
    return this.objects.get(`${bucket}:${key}`)?.length ?? null;
  }

  async readStart(bucket: StoryBucket, key: string, length: number): Promise<Uint8Array> {
    return (this.objects.get(`${bucket}:${key}`) ?? new Uint8Array(0)).subarray(0, length);
  }

  async deleteObject(bucket: StoryBucket, key: string): Promise<void> {
    this.objects.delete(`${bucket}:${key}`);
  }

  async deleteMediaFiles(storyId: string): Promise<void> {
    for (const key of [...this.objects.keys()]) if (key.startsWith(`media:${storyId}/`)) this.objects.delete(key);
    for (const key of [...this.mediaFiles]) if (key.startsWith(`${storyId}/`)) this.mediaFiles.delete(key);
  }

  mediaUrl(key: string): string {
    return `https://cdn.test/${key}`;
  }
}
