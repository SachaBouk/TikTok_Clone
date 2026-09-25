export interface PresignedPart {
  partNumber: number;
  url: string;
}

export interface UploadedPart {
  partNumber: number;
  // ETag renvoyé par le stockage dans la réponse au PUT de la partie.
  etag: string;
}

// Port du stockage objet des vidéos brutes (compatible S3 : MinIO en local, S3 ou R2 en production).
export abstract class VideoStorage {
  // Démarre un upload multipart et renvoie son identifiant.
  abstract startMultipartUpload(key: string, contentType: string): Promise<string>;
  // URLs signées pour envoyer chaque partie directement au stockage (PUT), sans passer par l'API.
  abstract presignPartUrls(key: string, uploadId: string, partCount: number, expiresInSeconds: number): Promise<PresignedPart[]>;
  // Assemble les parties. Lève UploadIncompleteError si des parties manquent ou si un ETag ne correspond pas.
  abstract completeMultipartUpload(key: string, uploadId: string, parts: UploadedPart[]): Promise<void>;
  abstract abortMultipartUpload(key: string, uploadId: string): Promise<void>;
  // Taille de l'objet en octets, ou null s'il n'existe pas.
  abstract getObjectSize(key: string): Promise<number | null>;
  abstract deleteObject(key: string): Promise<void>;
  // Fichiers publiés d'une vidéo (manifestes, segments, miniature), tous sous `<videoId>/` dans le bucket HLS.
  abstract deleteHlsFiles(videoId: string): Promise<void>;
}
