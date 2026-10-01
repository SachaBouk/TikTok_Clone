import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import type { AdminSuspendUserDto, VideoStatus } from '@repo/shared';
import { Transform, Type } from 'class-transformer';
import { IsBoolean, IsIn, IsInt, IsOptional, IsString, IsUUID, Matches, Max, MaxLength, Min } from 'class-validator';
import { MAX_SUSPENSION_REASON_LENGTH } from '../../auth/domain/auth-account';
import { DEFAULT_ADMIN_PAGE_SIZE, MAX_ADMIN_PAGE_SIZE } from '../domain/admin';

// Paramètres de requête validés par le ValidationPipe global (main.ts).

const VIDEO_STATUSES: VideoStatus[] = ['uploading', 'processing', 'ready', 'failed'];

class AdminPageQuery {
  @ApiPropertyOptional({ format: 'uuid', description: '`nextCursor` de la page précédente.' })
  @IsOptional()
  @IsUUID()
  cursor?: string;

  @ApiPropertyOptional({ type: 'integer', minimum: 1, maximum: MAX_ADMIN_PAGE_SIZE, default: DEFAULT_ADMIN_PAGE_SIZE })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(MAX_ADMIN_PAGE_SIZE)
  limit: number = DEFAULT_ADMIN_PAGE_SIZE;
}

export class AdminUsersQuery extends AdminPageQuery {
  @ApiPropertyOptional({ maxLength: 100, description: 'Pseudo (avec ou sans « @ »), nom ou identifiant ; partiel, sans tenir compte de la casse.' })
  @IsOptional()
  @IsString()
  @MaxLength(100)
  q?: string;
}

export class AdminVideosQuery extends AdminPageQuery {
  @ApiPropertyOptional({ enum: VIDEO_STATUSES, enumName: 'VideoStatus' })
  @IsOptional()
  @IsIn(VIDEO_STATUSES)
  status?: VideoStatus;

  @ApiPropertyOptional({ format: 'uuid', description: 'Vidéos de ce compte seulement.' })
  @IsOptional()
  @IsUUID()
  userId?: string;
}

export class AdminCommentsQuery extends AdminPageQuery {
  @ApiPropertyOptional({ format: 'uuid', description: 'Commentaires de cette vidéo seulement.' })
  @IsOptional()
  @IsUUID()
  videoId?: string;

  @ApiPropertyOptional({ format: 'uuid', description: 'Commentaires de ce compte seulement.' })
  @IsOptional()
  @IsUUID()
  userId?: string;
}

export class AdminWalletTransactionsQuery extends AdminPageQuery {
  @ApiPropertyOptional({ format: 'uuid', description: 'Mouvements de ce compte seulement.' })
  @IsOptional()
  @IsUUID()
  userId?: string;

  @ApiPropertyOptional({ type: Boolean, description: 'Seulement les mouvements d’un client inconnu, à rapprocher.' })
  @IsOptional()
  @Transform(({ value }) => (value === 'true' ? true : value === 'false' ? false : value))
  @IsBoolean()
  unmatched?: boolean;
}

// Suspension d'un compte (ADR-037) : motif interne obligatoire, nettoyé par le service.
export class AdminSuspendRequest implements AdminSuspendUserDto {
  @ApiProperty({ minLength: 1, maxLength: MAX_SUSPENSION_REASON_LENGTH, example: 'Spam répété dans les commentaires' })
  @IsString()
  @MaxLength(MAX_SUSPENSION_REASON_LENGTH)
  @Matches(/\S/, { message: 'Le motif est obligatoire' })
  reason!: string;
}
