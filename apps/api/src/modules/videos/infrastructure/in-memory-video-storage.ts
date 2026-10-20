import { createHash, randomUUID } from 'node:crypto';
import { UploadIncompleteError } from '../domain/video.errors';
import { PresignedPart, UploadedPart, VideoStorage } from '../domain/video-storage';

interface PendingUpload {
  key: string;
  // partNumber → { etag, taille }
  parts: Map<number, { etag: string; size: number }>;
}

// Adaptateur en mémoire pour les tests : simule le multipart S3 (ETags, parties manquantes, assemblage).
export class InMemoryVideoStorage extends VideoStorage {
  readonly uploads = new Map<string, PendingUpload>();
  readonly objects = new Map<string, number>();
  // Fichiers HLS publiés par le worker : identifiant de vidéo → clés sous `<videoId>/`.
  readonly hlsFiles = new Map<string, string[]>();

  async startMultipartUpload(key: string): Promise<string> {
    const uploadId = randomUUID();
    this.uploads.set(uploadId, { key, parts: new Map() });
    return uploadId;
  }

  async presignPartUrls(key: string, uploadId: string, partCount: number): Promise<PresignedPart[]> {
    return Array.from({ length: partCount }, (_, i) => ({ partNumber: i + 1, url: `memory://${key}?uploadId=${uploadId}&part=${i + 1}` }));
  }

  // Ce que ferait l'app avec l'URL signée : envoie une partie et reçoit son ETag.
  putPart(uploadId: string, partNumber: number, size: number): string {
    const upload = this.uploads.get(uploadId);
    if (!upload) throw new Error(`Upload inconnu : ${uploadId}`);
    const etag = `"${createHash('md5').update(`${uploadId}:${partNumber}:${size}`).digest('hex')}"`;
    upload.parts.set(partNumber, { etag, size });
    return etag;
  }

  async completeMultipartUpload(key: string, uploadId: string, parts: UploadedPart[]): Promise<void> {
    const upload = this.uploads.get(uploadId);
    if (!upload || upload.key !== key) throw new UploadIncompleteError('NoSuchUpload');
    if (parts.length === 0) throw new UploadIncompleteError('InvalidPart');
    for (const part of parts) {
      if (upload.parts.get(part.partNumber)?.etag !== part.etag) throw new UploadIncompleteError('InvalidPart');
    }
    const size = parts.reduce((total, part) => total + upload.parts.get(part.partNumber)!.size, 0);
    this.uploads.delete(uploadId);
    this.objects.set(key, size);
  }

  async abortMultipartUpload(_key: string, uploadId: string): Promise<void> {
    this.uploads.delete(uploadId);
  }

  // URLs d'un seul PUT signées (couverture, ADR-065) : clé → type et taille.
  readonly presignedPuts = new Map<string, { contentType: string; size: number }>();

  async presignPut(key: string, contentType: string, size: number): Promise<string> {
    this.presignedPuts.set(key, { contentType, size });
    return `memory://${key}`;
  }

  // Ce que ferait l'app avec l'URL signée d'un seul PUT.
  putObject(key: string, size: number): void {
    this.objects.set(key, size);
  }

  async getObjectSize(key: string): Promise<number | null> {
    return this.objects.get(key) ?? null;
  }

  async deleteObject(key: string): Promise<void> {
    this.objects.delete(key);
  }

  async deleteHlsFiles(videoId: string): Promise<void> {
    this.hlsFiles.delete(videoId);
  }
}
