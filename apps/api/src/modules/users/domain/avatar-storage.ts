import type { AvatarContentType } from './profile-rules';

export interface StoredObject {
  size: number;
  contentType: string | null;
}

// Port du stockage des photos de profil (compatible S3 : MinIO en local, S3 ou R2 en production).
// Bucket en lecture anonyme : l'URL publique d'un objet sert directement à l'app.
export abstract class AvatarStorage {
  // URL signée pour un PUT direct depuis l'app. Type et taille sont signés : le stockage refuse
  // un envoi qui ne les respecte pas exactement.
  abstract presignUpload(key: string, contentType: AvatarContentType, size: number, expiresInSeconds: number): Promise<string>;
  // Taille et type de l'objet, ou null s'il n'existe pas.
  abstract head(key: string): Promise<StoredObject | null>;
  // Premiers octets de l'objet (au plus `length`).
  abstract readStart(key: string, length: number): Promise<Uint8Array>;
  // Clés des objets sous `prefix`.
  abstract list(prefix: string): Promise<string[]>;
  abstract delete(keys: string[]): Promise<void>;
  abstract publicUrl(key: string): string;
}
