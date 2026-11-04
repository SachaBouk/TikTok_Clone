import { ApiProperty } from '@nestjs/swagger';
import type { PlusChangedEventDto } from '@repo/shared';
import { PlusStatusResponse } from './subscriptions.responses';

// Schéma OpenAPI de l'événement WebSocket (ADR-011), rattaché à l'union `RealtimeEvent` (src/openapi).
export class PlusChangedEvent implements PlusChangedEventDto {
  @ApiProperty({ enum: ['plusChanged'] })
  event!: 'plusChanged';

  @ApiProperty({ type: PlusStatusResponse })
  data!: PlusStatusResponse;
}
