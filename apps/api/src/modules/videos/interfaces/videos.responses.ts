import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import type { PendingVideosDto, UploadPartUrlDto, VideoDto, VideoLocationDto, VideoStatus, VideoUploadDto, VideoVisibility } from '@repo/shared';
import { VIDEO_VISIBILITIES, type Video } from '../domain/video';

// Schémas OpenAPI des DTO partagés : `implements` garantit à la compilation que chaque classe suit son type.

// Lieu de la publication (ADR-065) : nom et adresse affichée, jamais de coordonnées.
export class VideoLocationResponse implements VideoLocationDto {
  @ApiProperty()
  name!: string;

  @ApiPropertyOptional()
  address?: string;
}

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

  @ApiProperty({ description: "Étiquette « Contenu généré par l'IA » (ADR-065)." })
  aiGenerated!: boolean;

  // Absent sans lieu (ADR-065). Sans description : elle produirait un `allOf`.
  @ApiPropertyOptional({ type: VideoLocationResponse })
  location?: VideoLocationResponse;

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

  @ApiPropertyOptional({
    format: 'uri',
    description: 'Couverture demandée (ADR-065) : envoyer le JPEG en un seul PUT, avec `Content-Type: image/jpeg` et la taille déclarée.',
  })
  coverUrl?: string;
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
    aiGenerated: video.aiGenerated,
    ...locationOf(video),
    hlsUrl: video.hlsUrl,
    thumbnailUrl: video.thumbnailUrl,
    createdAt: video.createdAt.toISOString(),
  };
}

// Lieu (ADR-065) : `location` absent sans lieu, `address` absente sans adresse. Partagé avec le feed.
export function locationOf(video: { locationName: string | null; locationAddress: string | null }): { location?: VideoLocationDto } {
  if (!video.locationName) return {};
  return { location: { name: video.locationName, ...(video.locationAddress ? { address: video.locationAddress } : {}) } };
}
