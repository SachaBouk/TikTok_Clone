import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';
import { DEFAULT_VIEWERS_PAGE_SIZE, MAX_STORY_VIDEO_SIZE_BYTES, MAX_VIEWERS_PAGE_SIZE, SUPPORTED_STORY_TYPES } from '../../stories/domain/story';

// Corps et paramètres validés par le ValidationPipe global (main.ts) ; limites issues des règles du domaine.
// La confirmation reprend `CompleteUploadRequest` des vidéos (mêmes parties).

const STORY_TYPES = Object.keys(SUPPORTED_STORY_TYPES);

export class CreateStoryUploadRequest {
  @ApiProperty({ enum: STORY_TYPES, example: 'image/jpeg', description: 'Vidéo MP4 ou MOV (60 s au plus), ou photo JPEG 9:16.' })
  @IsIn(STORY_TYPES)
  contentType!: string;

  @ApiProperty({
    type: 'integer',
    minimum: 1,
    maximum: MAX_STORY_VIDEO_SIZE_BYTES,
    description: 'Taille du fichier en octets (photo : 5 Mio au plus).',
  })
  @IsInt()
  @Min(1)
  @Max(MAX_STORY_VIDEO_SIZE_BYTES)
  fileSize!: number;
}

export class StoryViewersQuery {
  @ApiPropertyOptional({ description: '`nextCursor` de la page précédente, tel quel.' })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  cursor?: string;

  @ApiPropertyOptional({ type: 'integer', minimum: 1, maximum: MAX_VIEWERS_PAGE_SIZE, default: DEFAULT_VIEWERS_PAGE_SIZE })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(MAX_VIEWERS_PAGE_SIZE)
  limit: number = DEFAULT_VIEWERS_PAGE_SIZE;
}
