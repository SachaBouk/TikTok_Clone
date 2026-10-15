import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import type { InterestCatalogDto, InterestDto, UserInterestsDto, UsernameAvailabilityDto, UsernameUnavailableReason } from '@repo/shared';
import type { Interest } from '../domain/interest-catalog';

// Schémas OpenAPI des DTO partagés de l'inscription (ADR-055) : `implements` garantit à la compilation que chaque
// classe suit son type.

const UNAVAILABLE_REASONS: UsernameUnavailableReason[] = ['invalid', 'reserved', 'taken'];

export class UsernameAvailabilityResponse implements UsernameAvailabilityDto {
  @ApiProperty()
  available!: boolean;

  // Pseudo indisponible : format invalide, pseudo réservé, ou déjà pris. Sans description (voir CLAUDE.md : un enum
  // nommé décrit produit un `allOf`).
  @ApiPropertyOptional({ enum: UNAVAILABLE_REASONS, enumName: 'UsernameUnavailableReason' })
  reason?: UsernameUnavailableReason;
}

export class InterestResponse implements InterestDto {
  @ApiProperty({ description: 'Code stable du catalogue.' })
  code!: string;

  @ApiProperty({ description: 'Libellé français.' })
  name!: string;

  @ApiProperty()
  emoji!: string;
}

export class InterestCatalogResponse implements InterestCatalogDto {
  @ApiProperty({ type: [InterestResponse] })
  items!: InterestResponse[];
}

export class UserInterestsResponse implements UserInterestsDto {
  @ApiProperty({ type: [String], description: 'Codes du catalogue, dans son ordre.' })
  interests!: string[];
}

export function toInterestDto(interest: Interest): InterestDto {
  return { code: interest.code, name: interest.name, emoji: interest.emoji };
}
