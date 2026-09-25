import { S3Client } from '@aws-sdk/client-s3';
import type { StorageConfig } from './storage.config';

// Client S3 (MinIO en local, S3 ou R2 en production, ADR-015). `endpoint` : l'hôte interne pour les appels
// de l'API, ou l'hôte public pour signer les URLs données à l'app.
export function createS3Client(config: StorageConfig, endpoint: string | undefined): S3Client {
  return new S3Client({
    region: config.region,
    endpoint,
    forcePathStyle: config.forcePathStyle,
    credentials: { accessKeyId: config.accessKeyId, secretAccessKey: config.secretAccessKey },
    // Depuis 2025, le SDK ajoute des sommes de contrôle CRC32 par défaut. Dans une URL signée,
    // elles obligeraient l'app à envoyer l'en-tête correspondant, et MinIO / R2 ne les gèrent pas toutes.
    requestChecksumCalculation: 'WHEN_REQUIRED',
    responseChecksumValidation: 'WHEN_REQUIRED',
  });
}
