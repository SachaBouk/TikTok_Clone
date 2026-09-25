import { ApiProperty } from '@nestjs/swagger';
import type { VideoProcessedEventDto } from '@repo/shared';
import { VideoResponse } from './videos.responses';

// Schéma OpenAPI de l'événement WebSocket (ADR-011), rattaché à l'union `RealtimeEvent` (src/openapi).
export class VideoProcessedEvent implements VideoProcessedEventDto {
  @ApiProperty({ enum: ['videoProcessed'] })
  event!: 'videoProcessed';

  @ApiProperty({ type: VideoResponse })
  data!: VideoResponse;
}
