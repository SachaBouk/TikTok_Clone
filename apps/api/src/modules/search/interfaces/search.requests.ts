import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsString, Max, MaxLength, Min, MinLength } from 'class-validator';
import { DEFAULT_HASHTAG_SUGGESTIONS, MAX_HASHTAG_SUGGESTIONS } from '../../videos/domain/hashtags';
import { DEFAULT_SEARCH_PAGE_SIZE, MAX_SEARCH_PAGE_SIZE, MAX_SEARCH_QUERY_LENGTH } from '../domain/search-rules';

export class AccountSearchQuery {
  @ApiProperty({ minLength: 1, maxLength: MAX_SEARCH_QUERY_LENGTH, description: 'Texte cherché dans le pseudo et le nom ; « @ » initial ignoré.' })
  @IsString()
  @MinLength(1)
  @MaxLength(MAX_SEARCH_QUERY_LENGTH)
  q!: string;

  @ApiPropertyOptional({ description: '`nextCursor` de la page précédente, tel quel.' })
  @IsOptional()
  @IsString()
  @MaxLength(100)
  cursor?: string;

  @ApiPropertyOptional({ type: 'integer', minimum: 1, maximum: MAX_SEARCH_PAGE_SIZE, default: DEFAULT_SEARCH_PAGE_SIZE })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(MAX_SEARCH_PAGE_SIZE)
  limit: number = DEFAULT_SEARCH_PAGE_SIZE;
}

export class HashtagSearchQuery {
  @ApiProperty({ minLength: 1, maxLength: 51, description: 'Début du nom du hashtag ; « # » initial ignoré.' })
  @IsString()
  @MinLength(1)
  @MaxLength(51)
  q!: string;

  @ApiPropertyOptional({ type: 'integer', minimum: 1, maximum: MAX_HASHTAG_SUGGESTIONS, default: DEFAULT_HASHTAG_SUGGESTIONS })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(MAX_HASHTAG_SUGGESTIONS)
  limit: number = DEFAULT_HASHTAG_SUGGESTIONS;
}
