import { ApiProperty } from '@nestjs/swagger';
import type { StoryProcessedEventDto } from '@repo/shared';
import { StoryResponse } from './stories.responses';

// Schéma OpenAPI de l'événement WebSocket (ADR-011), rattaché à l'union `RealtimeEvent` (src/openapi).
export class StoryProcessedEvent implements StoryProcessedEventDto {
  @ApiProperty({ enum: ['storyProcessed'] })
  event!: 'storyProcessed';

  @ApiProperty({ type: StoryResponse })
  data!: StoryResponse;
}
