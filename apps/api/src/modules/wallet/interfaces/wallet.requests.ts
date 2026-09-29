import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsUUID, Max, Min } from 'class-validator';
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
