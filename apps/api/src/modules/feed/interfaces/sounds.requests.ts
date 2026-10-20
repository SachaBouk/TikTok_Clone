import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import { ArrayMaxSize, ArrayMinSize, IsArray, IsInt, IsOptional, IsString, IsUUID, Max, MaxLength, Min, MinLength } from 'class-validator';
import { MAX_SOUND_IDS, MAX_SOUND_PAGE_SIZE, SOUND_PAGE_SIZE } from '../../videos/domain/video';

export class SoundPageQuery {
  @ApiPropertyOptional({ description: '`nextCursor` de la page précédente, tel quel.' })
  @IsOptional()
  @IsString()
  @MaxLength(10)
  cursor?: string;

  @ApiPropertyOptional({ type: 'integer', minimum: 1, maximum: MAX_SOUND_PAGE_SIZE, default: SOUND_PAGE_SIZE })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(MAX_SOUND_PAGE_SIZE)
  limit: number = SOUND_PAGE_SIZE;
}

export class SoundSearchQuery extends SoundPageQuery {
  @ApiProperty({ minLength: 1, maxLength: 50, description: 'Pseudo, nom ou description de la vidéo d’origine.' })
  @IsString()
  @MinLength(1)
  @MaxLength(50)
  q!: string;
}

export class SoundIdsQuery {
  // Paramètre répété (`ids=…&ids=…`) ; un seul identifiant arrive en chaîne.
  @ApiProperty({ type: [String], format: 'uuid', minItems: 1, maxItems: MAX_SOUND_IDS, description: 'Sons « Récents » de l’app.' })
  @Transform(({ value }: { value: unknown }) => (typeof value === 'string' ? [value] : value))
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(MAX_SOUND_IDS)
  @IsUUID('all', { each: true })
  ids!: string[];
}
