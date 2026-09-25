import { createWriteStream } from 'node:fs';
import { readdir, readFile } from 'node:fs/promises';
import { extname, join, relative } from 'node:path';
import type { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { GetObjectCommand, NoSuchKey, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import type { WorkerConfig } from './config';

// Le fichier brut n'existe pas (supprimé entre-temps) : inutile de réessayer.
export class RawVideoNotFoundError extends Error {
  constructor(key: string) {
    super(`Fichier brut introuvable : ${key}`);
    this.name = 'RawVideoNotFoundError';
  }
}

const CONTENT_TYPES: Record<string, string> = {
  '.m3u8': 'application/vnd.apple.mpegurl',
  '.ts': 'video/mp2t',
  '.jpg': 'image/jpeg',
};
// Chaque vidéo a son propre préfixe (videoId) et ses fichiers ne changent plus : cache CDN maximal.
const CACHE_CONTROL = 'public, max-age=31536000, immutable';
const UPLOAD_CONCURRENCY = 8;

// Stockage objet compatible S3 (ADR-015) : lecture du brut, écriture du HLS dans le bucket servi par le CDN.
export class VideoStorage {
  private readonly client: S3Client;

  constructor(private readonly config: WorkerConfig['s3']) {
    this.client = new S3Client({
      region: config.region,
      endpoint: config.endpoint,
      forcePathStyle: config.forcePathStyle,
      credentials: { accessKeyId: config.accessKeyId, secretAccessKey: config.secretAccessKey },
      // Sommes de contrôle CRC32 par défaut du SDK : MinIO et R2 ne les gèrent pas toutes (voir apps/api).
      requestChecksumCalculation: 'WHEN_REQUIRED',
      responseChecksumValidation: 'WHEN_REQUIRED',
    });
  }

  // Télécharge en flux : la vidéo brute (jusqu'à 1 Gio) ne passe jamais entièrement en mémoire.
  async downloadRaw(key: string, destination: string): Promise<void> {
    try {
      const { Body } = await this.client.send(new GetObjectCommand({ Bucket: this.config.rawBucket, Key: key }));
      await pipeline(Body as Readable, createWriteStream(destination));
    } catch (error) {
      if (error instanceof NoSuchKey) throw new RawVideoNotFoundError(key);
      throw error;
    }
  }

  // Envoie tout le contenu de `directory` sous `<prefix>/` dans le bucket HLS.
  async uploadHls(directory: string, prefix: string): Promise<void> {
    const files = await listFiles(directory);
    for (let i = 0; i < files.length; i += UPLOAD_CONCURRENCY) {
      await Promise.all(
        files.slice(i, i + UPLOAD_CONCURRENCY).map(async (file) =>
          this.client.send(
            new PutObjectCommand({
              Bucket: this.config.hlsBucket,
              Key: `${prefix}/${relative(directory, file)}`,
              Body: await readFile(file),
              ContentType: CONTENT_TYPES[extname(file)] ?? 'application/octet-stream',
              CacheControl: CACHE_CONTROL,
            }),
          ),
        ),
      );
    }
  }
}

async function listFiles(directory: string): Promise<string[]> {
  const entries = await readdir(directory, { withFileTypes: true, recursive: true });
  return entries.filter((entry) => entry.isFile()).map((entry) => join(entry.parentPath, entry.name));
}
