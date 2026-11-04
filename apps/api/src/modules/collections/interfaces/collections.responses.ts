import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import type { CollectionDto, CollectionListDto } from '@repo/shared';
import { toUserSummary, UserSummaryResponse } from '../../users/interfaces/user-summary.response';
import type { CollectionView } from '../domain/collection';

// Collection de favoris (ADR-072). `implements` garantit à la compilation que la classe suit le type partagé.
export class CollectionResponse implements CollectionDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty({ example: 'Recettes' })
  name!: string;

  @ApiProperty({ enum: ['public', 'private'], enumName: 'VideoVisibility' })
  visibility!: 'public' | 'private';

  @ApiProperty({ type: 'integer', minimum: 0 })
  videosCount!: number;

  // Miniature de la dernière vidéo visible du lecteur ; nulle pour une collection vide.
  @ApiProperty({ type: String, nullable: true, format: 'uri' })
  coverUrl!: string | null;

  @ApiProperty({ type: UserSummaryResponse })
  owner!: UserSummaryResponse;

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;

  @ApiProperty({ format: 'date-time' })
  updatedAt!: string;

  // Avec `?videoId=` seulement.
  @ApiPropertyOptional()
  containsVideo?: boolean;
}

export class CollectionListResponse implements CollectionListDto {
  @ApiProperty({ type: [CollectionResponse] })
  items!: CollectionResponse[];
}

// Mapping explicite, partagé avec la carte d'un message (module messaging).
export function toCollectionDto({ collection, coverUrl, owner, containsVideo }: CollectionView): CollectionDto {
  return {
    id: collection.id,
    name: collection.name,
    visibility: collection.visibility,
    videosCount: collection.videosCount,
    coverUrl,
    owner: toUserSummary(owner),
    createdAt: collection.createdAt.toISOString(),
    updatedAt: collection.updatedAt.toISOString(),
    ...(containsVideo !== undefined && { containsVideo }),
  };
}
