import { ApiProperty } from '@nestjs/swagger';
import type { WalletUpdatedEventDto } from '@repo/shared';
import { WalletResponse } from './wallet.responses';

// Schéma OpenAPI de l'événement WebSocket (ADR-011), rattaché à l'union `RealtimeEvent` (src/openapi).
export class WalletUpdatedEvent implements WalletUpdatedEventDto {
  @ApiProperty({ enum: ['walletUpdated'] })
  event!: 'walletUpdated';

  @ApiProperty({ type: WalletResponse })
  data!: WalletResponse;
}
