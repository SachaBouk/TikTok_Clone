import {
  DeleteObjectsCommand,
  GetObjectCommand,
  HeadObjectCommand,
  ListObjectsV2Command,
  PutObjectCommand,
  type S3Client,
  S3ServiceException,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { createS3Client } from '../../../storage/s3-client';
import type { StorageConfig } from '../../../storage/storage.config';
import { AvatarStorage, type StoredObject } from '../domain/avatar-storage';
import type { AvatarContentType } from '../domain/profile-rules';

// Limite S3 de DeleteObjects.
const DELETE_BATCH_SIZE = 1000;

// Adaptateur S3 du bucket des photos de profil (MinIO en local, S3 ou R2 en production, ADR-015).
export class S3AvatarStorage extends AvatarStorage {
  // Appels faits par l'API elle-même.
  private readonly client: S3Client;
  // Signature des URLs données à l'app, avec l'hôte public.
  private readonly presigner: S3Client;

  constructor(private readonly config: StorageConfig) {
    super();
    this.client = createS3Client(config, config.endpoint);
    this.presigner = createS3Client(config, config.publicEndpoint);
  }

  presignUpload(key: string, contentType: AvatarContentType, size: number, expiresInSeconds: number): Promise<string> {
    const command = new PutObjectCommand({ Bucket: this.config.avatarsBucket, Key: key, ContentType: contentType, ContentLength: size });
    // Le SDK ne signe pas Content-Type par défaut (ni Content-Length s'il n'est pas demandé) : on les impose,
    // pour que le stockage refuse un fichier d'un autre type ou d'une autre taille (403).
    return getSignedUrl(this.presigner, command, {
      expiresIn: expiresInSeconds,
      signableHeaders: new Set(['content-type', 'content-length']),
    });
  }

  async head(key: string): Promise<StoredObject | null> {
    try {
      const { ContentLength, ContentType } = await this.client.send(new HeadObjectCommand({ Bucket: this.config.avatarsBucket, Key: key }));
      return { size: ContentLength ?? 0, contentType: ContentType ?? null };
    } catch (error) {
      if (error instanceof S3ServiceException && error.$metadata.httpStatusCode === 404) return null;
      throw error;
    }
  }

  async readStart(key: string, length: number): Promise<Uint8Array> {
    const { Body } = await this.client.send(
      new GetObjectCommand({ Bucket: this.config.avatarsBucket, Key: key, Range: `bytes=0-${length - 1}` }),
    );
    return Body ? Body.transformToByteArray() : new Uint8Array();
  }

  async list(prefix: string): Promise<string[]> {
    const keys: string[] = [];
    let token: string | undefined;
    do {
      const page = await this.client.send(
        new ListObjectsV2Command({ Bucket: this.config.avatarsBucket, Prefix: prefix, ContinuationToken: token }),
      );
      for (const object of page.Contents ?? []) if (object.Key) keys.push(object.Key);
      token = page.IsTruncated ? page.NextContinuationToken : undefined;
    } while (token);
    return keys;
  }

  async delete(keys: string[]): Promise<void> {
    for (let i = 0; i < keys.length; i += DELETE_BATCH_SIZE) {
      const batch = keys.slice(i, i + DELETE_BATCH_SIZE);
      const { Errors } = await this.client.send(
        new DeleteObjectsCommand({ Bucket: this.config.avatarsBucket, Delete: { Objects: batch.map((Key) => ({ Key })), Quiet: true } }),
      );
      if (Errors?.length) throw new Error(`Suppression de photos de profil impossible : ${Errors.map((e) => `${e.Key} (${e.Code})`).join(', ')}`);
    }
  }

  publicUrl(key: string): string {
    return `${this.config.avatarsPublicBaseUrl}/${key}`;
  }
}
