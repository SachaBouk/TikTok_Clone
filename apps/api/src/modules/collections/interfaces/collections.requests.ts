import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { ArrayMaxSize, ArrayMinSize, IsArray, IsIn, IsOptional, IsString, IsUUID, MaxLength, MinLength } from 'class-validator';
import { COLLECTION_VISIBILITIES, MAX_COLLECTION_BATCH, MAX_COLLECTION_NAME_LENGTH } from '../domain/collection';

// Corps et paramètres validés par le ValidationPipe global (main.ts) ; le service nettoie le nom.

export class CreateCollectionRequest {
  @ApiProperty({ minLength: 1, maxLength: MAX_COLLECTION_NAME_LENGTH, example: 'Recettes' })
  @IsString()
  @MinLength(1)
  @MaxLength(MAX_COLLECTION_NAME_LENGTH)
  name!: string;

  @ApiPropertyOptional({ enum: COLLECTION_VISIBILITIES, enumName: 'VideoVisibility' })
  @IsOptional()
  @IsIn(COLLECTION_VISIBILITIES)
  visibility?: 'public' | 'private';

  @ApiPropertyOptional({ type: [String], format: 'uuid', maxItems: MAX_COLLECTION_BATCH, description: 'Vidéos ajoutées aussitôt (mises en favori).' })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(MAX_COLLECTION_BATCH)
  @IsUUID('all', { each: true })
  videoIds?: string[];
}

export class UpdateCollectionRequest {
  @ApiPropertyOptional({ minLength: 1, maxLength: MAX_COLLECTION_NAME_LENGTH, example: 'Recettes' })
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(MAX_COLLECTION_NAME_LENGTH)
  name?: string;

  @ApiPropertyOptional({ enum: COLLECTION_VISIBILITIES, enumName: 'VideoVisibility' })
  @IsOptional()
  @IsIn(COLLECTION_VISIBILITIES)
  visibility?: 'public' | 'private';
}

export class CollectionVideosRequest {
  @ApiProperty({ type: [String], format: 'uuid', minItems: 1, maxItems: MAX_COLLECTION_BATCH })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(MAX_COLLECTION_BATCH)
  @IsUUID('all', { each: true })
  videoIds!: string[];
}

export class RemoveCollectionVideosQuery {
  @ApiProperty({
    type: [String],
    format: 'uuid',
    minItems: 1,
    maxItems: MAX_COLLECTION_BATCH,
    description: 'Vidéos à retirer, paramètre répété (`?videoIds=…&videoIds=…`).',
  })
  // Un seul identifiant arrive en chaîne, plusieurs en tableau.
  @Transform(({ value }: { value: unknown }) => (typeof value === 'string' ? [value] : value))
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(MAX_COLLECTION_BATCH)
  @IsUUID('all', { each: true })
  videoIds!: string[];
}

export class MyCollectionsQuery {
  @ApiPropertyOptional({ format: 'uuid', description: 'Avec une vidéo : chaque collection dit si elle la contient (`containsVideo`).' })
  @IsOptional()
  @IsUUID()
  videoId?: string;
}
