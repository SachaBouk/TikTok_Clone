import { ApiProperty } from '@nestjs/swagger';
import type { ProfileCountersChangedEventDto } from '@repo/shared';

// Schéma OpenAPI de l'événement WebSocket (ADR-011), rattaché à l'union `RealtimeEvent` (src/openapi).

export class ProfileCountersData {
  @ApiProperty({ type: 'integer', minimum: 0 })
  followersCount!: number;

  @ApiProperty({ type: 'integer', minimum: 0 })
  followingCount!: number;
}

// Compteurs du profil du compte connecté (ADR-045), après un abonnement, un désabonnement ou un blocage.
export class ProfileCountersChangedEvent implements ProfileCountersChangedEventDto {
  @ApiProperty({ enum: ['profileCountersChanged'] })
  event!: 'profileCountersChanged';

  @ApiProperty({ type: ProfileCountersData })
  data!: ProfileCountersData;
}
