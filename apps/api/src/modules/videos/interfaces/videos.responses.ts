import { ApiProperty } from '@nestjs/swagger';
import type { PendingVideosDto, UploadPartUrlDto, VideoDto, VideoStatus, VideoUploadDto, VideoVisibility } from '@repo/shared';
import { VIDEO_VISIBILITIES, type Video } from '../domain/video';

// Schémas OpenAPI des DTO partagés : `implements` garantit à la compilation que chaque classe suit son type.

export class VideoResponse implements VideoDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty({ format: 'uuid', description: 'Auteur de la vidéo.' })
  userId!: string;

  @ApiProperty({ type: String, nullable: true })
  description!: string | null;

  @ApiProperty({ enum: ['uploading', 'processing', 'ready', 'failed'], enumName: 'VideoStatus' })
  status!: VideoStatus;

  // Privée (ADR-061) : visible de son seul auteur.
  @ApiProperty({ enum: VIDEO_VISIBILITIES, enumName: 'VideoVisibility' })
  visibility!: VideoVisibility;

  @ApiProperty({ description: 'Commentaires autorisés (ADR-062).' })
  commentsEnabled!: boolean;

  @ApiProperty({ description: "« Autoriser l'utilisation de mon son » (ADR-064)." })
  soundShared!: boolean;

  @ApiProperty({ type: String, nullable: true, format: 'uri', description: 'Manifeste HLS, quand la vidéo est `ready`.' })
  hlsUrl!: string | null;

  @ApiProperty({ type: String, nullable: true, format: 'uri' })
  thumbnailUrl!: string | null;

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;
}

export class UploadPartUrlResponse implements UploadPartUrlDto {
  @ApiProperty({ type: 'integer', minimum: 1 })
  partNumber!: number;

  @ApiProperty({ format: 'uri', description: 'URL signée : envoyer la partie en PUT, garder l’en-tête `ETag` de la réponse.' })
  url!: string;
}

export class VideoUploadResponse implements VideoUploadDto {
  @ApiProperty({ type: VideoResponse })
  video!: VideoResponse;

  @ApiProperty({ type: 'integer', description: 'Taille de chaque partie en octets ; la dernière peut être plus petite.' })
  partSize!: number;

  @ApiProperty({ type: [UploadPartUrlResponse] })
  parts!: UploadPartUrlResponse[];

  @ApiProperty({ format: 'date-time', description: 'Expiration des URLs signées.' })
  expiresAt!: string;
}

export class PendingVideosResponse implements PendingVideosDto {
  @ApiProperty({ type: [VideoResponse], description: 'En traitement ou en échec, de la plus récente à la plus ancienne (50 au plus).' })
  items!: VideoResponse[];
}

// Mapping explicite : rawKey et uploadId restent internes à l'API. Partagé par le controller et
// les événements WebSocket (RealtimeVideoEventPublisher).
export function toVideoDto(video: Video): VideoDto {
  return {
    id: video.id,
    userId: video.userId,
    description: video.description,
    status: video.status,
    visibility: video.visibility,
    commentsEnabled: video.commentsEnabled,
    soundShared: video.soundShared,
    hlsUrl: video.hlsUrl,
    thumbnailUrl: video.thumbnailUrl,
    createdAt: video.createdAt.toISOString(),
  };
}
