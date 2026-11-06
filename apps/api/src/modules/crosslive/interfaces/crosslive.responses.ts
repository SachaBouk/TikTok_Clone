import { ApiProperty } from '@nestjs/swagger';
import type { LiveParticipantTokenDto } from '@repo/shared';

export class LiveParticipantTokenResponse implements LiveParticipantTokenDto {
  @ApiProperty({ description: 'JWT HS256 de 5 min, à présenter au serveur commun du Live (SDK d’echimine).' })
  token!: string;
}
