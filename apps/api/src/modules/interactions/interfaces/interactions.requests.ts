import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import { ArrayMaxSize, ArrayMinSize, IsArray, IsInt, IsOptional, IsString, IsUUID, Max, MaxLength, Min, MinLength } from 'class-validator';
import {
  DEFAULT_COMMENTS_PAGE_SIZE,
  DEFAULT_FOLLOWS_PAGE_SIZE,
  DEFAULT_SUGGESTIONS,
  MAX_COMMENT_LENGTH,
  MAX_COMMENTS_PAGE_SIZE,
  MAX_FOLLOWS_PAGE_SIZE,
  MAX_RELATIONSHIP_IDS,
  MAX_SUGGESTIONS,
} from '../domain/interaction';

// Corps et paramètres de requête validés par le ValidationPipe global (main.ts).

export class CreateCommentRequest {
  @ApiProperty({ minLength: 1, maxLength: MAX_COMMENT_LENGTH, example: 'Trop bien !' })
  @IsString()
  @MinLength(1)
  @MaxLength(MAX_COMMENT_LENGTH)
  content!: string;

  @ApiPropertyOptional({ format: 'uuid', description: 'Réponse (ADR-060) : commentaire ou réponse de la même vidéo auquel on répond.' })
  @IsOptional()
  @IsUUID()
  replyToId?: string;
}

export class CommentsQuery {
  @ApiPropertyOptional({ format: 'uuid', description: '`nextCursor` de la page précédente.' })
  @IsOptional()
  @IsUUID()
  cursor?: string;

  @ApiPropertyOptional({ type: 'integer', minimum: 1, maximum: MAX_COMMENTS_PAGE_SIZE, default: DEFAULT_COMMENTS_PAGE_SIZE })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(MAX_COMMENTS_PAGE_SIZE)
  limit: number = DEFAULT_COMMENTS_PAGE_SIZE;
}

export class FollowsQuery {
  @ApiPropertyOptional({ description: '`nextCursor` de la page précédente, tel quel.' })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  cursor?: string;

  @ApiPropertyOptional({ type: 'integer', minimum: 1, maximum: MAX_FOLLOWS_PAGE_SIZE, default: DEFAULT_FOLLOWS_PAGE_SIZE })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(MAX_FOLLOWS_PAGE_SIZE)
  limit: number = DEFAULT_FOLLOWS_PAGE_SIZE;
}

export class RelationshipsQuery {
  @ApiProperty({
    type: [String],
    format: 'uuid',
    minItems: 1,
    maxItems: MAX_RELATIONSHIP_IDS,
    description: 'Identifiants des comptes, paramètre répété (`?userIds=…&userIds=…`).',
  })
  // Un seul identifiant arrive en chaîne, plusieurs en tableau.
  @Transform(({ value }: { value: unknown }) => (typeof value === 'string' ? [value] : value))
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(MAX_RELATIONSHIP_IDS)
  @IsUUID('all', { each: true })
  userIds!: string[];
}

export class SuggestionsQuery {
  @ApiPropertyOptional({ type: 'integer', minimum: 1, maximum: MAX_SUGGESTIONS, default: DEFAULT_SUGGESTIONS })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(MAX_SUGGESTIONS)
  limit: number = DEFAULT_SUGGESTIONS;
}
