import {
  AbortMultipartUploadCommand,
  CompleteMultipartUploadCommand,
  CreateMultipartUploadCommand,
  DeleteObjectCommand,
  DeleteObjectsCommand,
  HeadObjectCommand,
  ListObjectsV2Command,
  type S3Client,
  S3ServiceException,
  UploadPartCommand,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { UploadIncompleteError } from '../domain/video.errors';
import { PresignedPart, UploadedPart, VideoStorage } from '../domain/video-storage';
import { createS3Client } from '../../../storage/s3-client';
import type { StorageConfig } from '../../../storage/storage.config';

// Erreurs S3 qui signifient « parties manquantes ou incorrectes » : l'app peut les renvoyer.
const INCOMPLETE_UPLOAD_ERRORS = new Set(['InvalidPart', 'InvalidPartOrder', 'NoSuchUpload', 'EntityTooSmall']);

// Adaptateur S3 (MinIO en local, S3 ou R2 en production, ADR-015).
export class S3VideoStorage extends VideoStorage {
  // Appels faits par l'API elle-même.
  private readonly client: S3Client;
  // Signature des URLs données à l'app, avec l'hôte public.
  private readonly presigner: S3Client;

  constructor(private readonly config: StorageConfig) {
    super();
    this.client = createS3Client(config, config.endpoint);
    this.presigner = createS3Client(config, config.publicEndpoint);
  }

  async startMultipartUpload(key: string, contentType: string): Promise<string> {
    const { UploadId } = await this.client.send(
      new CreateMultipartUploadCommand({ Bucket: this.config.rawBucket, Key: key, ContentType: contentType }),
    );
    if (!UploadId) throw new Error(`Le stockage n'a pas renvoyé d'UploadId pour ${key}`);
    return UploadId;
  }

  presignPartUrls(key: string, uploadId: string, partCount: number, expiresInSeconds: number): Promise<PresignedPart[]> {
    return Promise.all(
      Array.from({ length: partCount }, async (_, index) => {
        const partNumber = index + 1;
        const command = new UploadPartCommand({ Bucket: this.config.rawBucket, Key: key, UploadId: uploadId, PartNumber: partNumber });
        return { partNumber, url: await getSignedUrl(this.presigner, command, { expiresIn: expiresInSeconds }) };
      }),
    );
  }

  async completeMultipartUpload(key: string, uploadId: string, parts: UploadedPart[]): Promise<void> {
    try {
      await this.client.send(
        new CompleteMultipartUploadCommand({
          Bucket: this.config.rawBucket,
          Key: key,
          UploadId: uploadId,
          MultipartUpload: { Parts: parts.map((p) => ({ PartNumber: p.partNumber, ETag: p.etag })) },
        }),
      );
    } catch (error) {
      if (error instanceof S3ServiceException && INCOMPLETE_UPLOAD_ERRORS.has(error.name)) {
        throw new UploadIncompleteError(error.name);
      }
      throw error;
    }
  }

  async abortMultipartUpload(key: string, uploadId: string): Promise<void> {
    try {
      await this.client.send(new AbortMultipartUploadCommand({ Bucket: this.config.rawBucket, Key: key, UploadId: uploadId }));
    } catch (error) {
      if (!(error instanceof S3ServiceException && error.name === 'NoSuchUpload')) throw error;
    }
  }

  async getObjectSize(key: string): Promise<number | null> {
    try {
      const { ContentLength } = await this.client.send(new HeadObjectCommand({ Bucket: this.config.rawBucket, Key: key }));
      return ContentLength ?? null;
    } catch (error) {
      if (error instanceof S3ServiceException && error.$metadata.httpStatusCode === 404) return null;
      throw error;
    }
  }

  async deleteObject(key: string): Promise<void> {
    await this.client.send(new DeleteObjectCommand({ Bucket: this.config.rawBucket, Key: key }));
  }

  // Par pages de 1 000 clés (limite de ListObjectsV2 et de DeleteObjects).
  async deleteHlsFiles(videoId: string): Promise<void> {
    let token: string | undefined;
    do {
      const page = await this.client.send(
        new ListObjectsV2Command({ Bucket: this.config.hlsBucket, Prefix: `${videoId}/`, ContinuationToken: token }),
      );
      const keys = (page.Contents ?? []).flatMap((object) => (object.Key ? [{ Key: object.Key }] : []));
      if (keys.length > 0) {
        const { Errors } = await this.client.send(
          new DeleteObjectsCommand({ Bucket: this.config.hlsBucket, Delete: { Objects: keys, Quiet: true } }),
        );
        if (Errors?.length) throw new Error(`Suppression HLS incomplète pour ${videoId} : ${Errors.map((e) => `${e.Key} (${e.Code})`).join(', ')}`);
      }
      token = page.IsTruncated ? page.NextContinuationToken : undefined;
    } while (token);
  }
}
