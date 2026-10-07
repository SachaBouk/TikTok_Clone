import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsString, IsUUID, Max, MaxLength, Min } from 'class-validator';
import { DEFAULT_TRANSACTIONS_PAGE_SIZE, MAX_TRANSACTIONS_PAGE_SIZE } from '../domain/wallet';

export class WalletTransactionsQuery {
  @ApiPropertyOptional({ format: 'uuid', description: '`nextCursor` de la page précédente.' })
  @IsOptional()
  @IsUUID()
  cursor?: string;

  @ApiPropertyOptional({ type: 'integer', minimum: 1, maximum: MAX_TRANSACTIONS_PAGE_SIZE, default: DEFAULT_TRANSACTIONS_PAGE_SIZE })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(MAX_TRANSACTIONS_PAGE_SIZE)
  limit: number = DEFAULT_TRANSACTIONS_PAGE_SIZE;
}

// Cadeau sur une vidéo (ADR-050).
export class SendGiftRequest {
  @ApiProperty({ description: 'Code du cadeau dans le catalogue (`GET /gifts/catalog`).', maxLength: 50 })
  @IsString()
  @MaxLength(50)
  gift!: string;

  @ApiProperty({ format: 'uuid', description: 'Identifiant d’envoi choisi par l’app, le même à chaque essai : un renvoi ne débite pas deux fois.' })
  @IsUUID()
  clientGiftId!: string;
}
