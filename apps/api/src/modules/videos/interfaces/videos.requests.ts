import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsBoolean,
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsIn,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';
import { MAX_DESCRIPTION_LENGTH, MAX_VIDEO_SIZE_BYTES, SUPPORTED_VIDEO_TYPES } from '../domain/upload-rules';
import { VIDEO_VISIBILITIES, type VideoVisibility } from '../domain/video';

// Corps de requête validés par le ValidationPipe global (main.ts) ; limites issues des règles du domaine.

const VIDEO_TYPES = Object.keys(SUPPORTED_VIDEO_TYPES);
// Limite S3 du nombre de parties d'un upload multipart.
const MAX_PARTS = 10_000;

export class CreateUploadRequest {
  @ApiProperty({ enum: VIDEO_TYPES, example: 'video/quicktime' })
  @IsIn(VIDEO_TYPES)
  contentType!: string;

  @ApiProperty({ type: 'integer', minimum: 1, maximum: MAX_VIDEO_SIZE_BYTES, description: 'Taille du fichier en octets.' })
  @IsInt()
  @Min(1)
  @Max(MAX_VIDEO_SIZE_BYTES)
  fileSize!: number;

  @ApiPropertyOptional({ maxLength: MAX_DESCRIPTION_LENGTH })
  @IsOptional()
  @IsString()
  @MaxLength(MAX_DESCRIPTION_LENGTH)
  description?: string;

  // Publique par défaut (ADR-061). Pas de description : sur un enum nommé, elle produirait un `allOf`.
  @ApiPropertyOptional({ enum: VIDEO_VISIBILITIES, enumName: 'VideoVisibility' })
  @IsOptional()
  @IsIn(VIDEO_VISIBILITIES)
  visibility?: VideoVisibility;

  @ApiPropertyOptional({ description: 'Commentaires autorisés (ADR-062), vrai par défaut.' })
  @IsOptional()
  @IsBoolean()
  commentsEnabled?: boolean;
}

export class SetVideoVisibilityRequest {
  @ApiProperty({ enum: VIDEO_VISIBILITIES, enumName: 'VideoVisibility' })
  @IsIn(VIDEO_VISIBILITIES)
  visibility!: VideoVisibility;
}

export class SetCommentSettingsRequest {
  @ApiProperty({ description: 'Commentaires autorisés (ADR-062).' })
  @IsBoolean()
  commentsEnabled!: boolean;
}

export class UploadedPartRequest {
  @ApiProperty({ type: 'integer', minimum: 1, maximum: MAX_PARTS })
  @IsInt()
  @Min(1)
  @Max(MAX_PARTS)
  partNumber!: number;

  @ApiProperty({ description: 'En-tête `ETag` de la réponse au PUT de la partie, tel quel.' })
  @IsString()
  @IsNotEmpty()
  @MaxLength(200)
  etag!: string;
}

export class CompleteUploadRequest {
  @ApiProperty({ type: [UploadedPartRequest], minItems: 1, maxItems: MAX_PARTS })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(MAX_PARTS)
  @ValidateNested({ each: true })
  @Type(() => UploadedPartRequest)
  parts!: UploadedPartRequest[];
}
