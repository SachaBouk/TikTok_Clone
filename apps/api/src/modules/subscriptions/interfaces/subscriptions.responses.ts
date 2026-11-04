import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import type { PlusPeriod, PlusStatusDto } from '@repo/shared';
import type { PlusStatus } from '../domain/plus-subscription';

// État de l'abonnement « Plus » (ADR-073).
export class PlusStatusResponse implements PlusStatusDto {
  @ApiProperty({ description: 'Abonné : échéance dans le futur.' })
  active!: boolean;

  @ApiPropertyOptional({ enum: ['monthly', 'annual'], enumName: 'PlusPeriod' })
  period?: PlusPeriod;

  @ApiPropertyOptional({ format: 'date-time', description: 'Échéance, période de grâce comprise.' })
  expiresAt?: string;

  @ApiPropertyOptional({ description: 'Faux : renouvellement annulé, actif jusqu’à l’échéance.' })
  willRenew?: boolean;
}

// Mapping explicite : store et environnement restent internes.
export function toPlusStatusDto({ active, subscription }: PlusStatus): PlusStatusDto {
  if (!subscription) return { active };
  return { active, period: subscription.period, expiresAt: subscription.expiresAt.toISOString(), willRenew: subscription.willRenew };
}
