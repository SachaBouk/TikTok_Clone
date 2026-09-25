import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';
import { DEFAULT_GRID_PAGE_SIZE, DEFAULT_PAGE_SIZE, MAX_GRID_PAGE_SIZE, MAX_PAGE_SIZE } from '../domain/feed-rules';

// Paramètres de requête validés par le ValidationPipe global (main.ts, `transform: true` pour `limit`).
export class FeedQuery {
  @ApiPropertyOptional({ description: '`nextCursor` de la page précédente ; absent pour démarrer une nouvelle session.' })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  cursor?: string;

  @ApiPropertyOptional({ type: 'integer', minimum: 1, maximum: MAX_PAGE_SIZE, default: DEFAULT_PAGE_SIZE })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(MAX_PAGE_SIZE)
  limit: number = DEFAULT_PAGE_SIZE;
}

export class VideoGridQuery {
  @ApiPropertyOptional({ description: '`nextCursor` de la page précédente, tel quel.' })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  cursor?: string;

  @ApiPropertyOptional({ type: 'integer', minimum: 1, maximum: MAX_GRID_PAGE_SIZE, default: DEFAULT_GRID_PAGE_SIZE })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(MAX_GRID_PAGE_SIZE)
  limit: number = DEFAULT_GRID_PAGE_SIZE;
}
