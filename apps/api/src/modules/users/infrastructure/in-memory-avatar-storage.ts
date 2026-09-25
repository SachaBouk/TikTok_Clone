import type { AvatarContentType } from '../domain/profile-rules';
import { AvatarStorage, type StoredObject } from '../domain/avatar-storage';

interface MemoryObject {
  contentType: string;
  bytes: Uint8Array;
}

// Adaptateur en mémoire pour les tests : simule le bucket des photos de profil et l'URL signée.
export class InMemoryAvatarStorage extends AvatarStorage {
  readonly objects = new Map<string, MemoryObject>();
  // Envois autorisés par une URL signée : clé → type et taille signés.
  private readonly presigned = new Map<string, { contentType: AvatarContentType; size: number }>();

  async presignUpload(key: string, contentType: AvatarContentType, size: number): Promise<string> {
    this.presigned.set(key, { contentType, size });
    return `memory://avatars/${key}`;
  }

  // Ce que ferait l'app avec l'URL signée. Comme S3, refuse un type ou une taille différents de ceux signés.
  put(url: string, contentType: string, bytes: Uint8Array): void {
    const key = url.replace('memory://avatars/', '');
    const signed = this.presigned.get(key);
    if (!signed || signed.contentType !== contentType || signed.size !== bytes.length) throw new Error('403 SignatureDoesNotMatch');
    this.objects.set(key, { contentType, bytes });
  }

  async head(key: string): Promise<StoredObject | null> {
    const object = this.objects.get(key);
    return object ? { size: object.bytes.length, contentType: object.contentType } : null;
  }

  async readStart(key: string, length: number): Promise<Uint8Array> {
    return this.objects.get(key)?.bytes.subarray(0, length) ?? new Uint8Array();
  }

  async list(prefix: string): Promise<string[]> {
    return [...this.objects.keys()].filter((key) => key.startsWith(prefix));
  }

  async delete(keys: string[]): Promise<void> {
    for (const key of keys) this.objects.delete(key);
  }

  publicUrl(key: string): string {
    return `https://cdn.test/avatars/${key}`;
  }
}
