import { ApiProperty } from '@nestjs/swagger';
import type { LiveChatMessageDeletedDto, LiveEndedEventDto, LiveEndReason, LiveGiftEventDto, LiveHeartsEventDto } from '@repo/shared';
import { UserSummaryResponse } from '../../users/interfaces/user-summary.response';
import { GiftResponse } from '../../wallet/interfaces/wallet.responses';
import { LIVE_END_REASONS } from '../domain/live';
import { LiveChatMessageResponse } from './live.responses';

// Schémas OpenAPI des événements diffusés dans la salle d'un live (messages de données de LiveKit, sujet `live`,
// ADR-053), réunis dans l'union `LiveRoomEvent` (src/openapi) que l'app décode avec les types générés.

export class LiveChatMessageDeletedResponse implements LiveChatMessageDeletedDto {
  @ApiProperty({ format: 'uuid' })
  messageId!: string;
}

export class LiveHeartsEventResponse implements LiveHeartsEventDto {
  @ApiProperty({ type: 'integer', minimum: 1, description: 'Cœurs de ce lot.' })
  count!: number;

  @ApiProperty({ type: 'integer', minimum: 0, description: 'Total du live.' })
  total!: number;
}

export class LiveGiftEventResponse implements LiveGiftEventDto {
  @ApiProperty({ type: UserSummaryResponse })
  sender!: UserSummaryResponse;

  @ApiProperty({ type: GiftResponse })
  gift!: GiftResponse;

  @ApiProperty({ type: 'integer', minimum: 1, description: 'Prix payé, en jetons.' })
  amount!: number;

  @ApiProperty({ type: 'integer', minimum: 1, description: 'Cadeaux reçus par le live, celui-ci compris.' })
  giftsCount!: number;

  @ApiProperty({ type: 'integer', minimum: 1, description: 'Jetons reçus par le live, celui-ci compris.' })
  giftsAmount!: number;
}

export class LiveEndedEventResponse implements LiveEndedEventDto {
  @ApiProperty({ enum: LIVE_END_REASONS, enumName: 'LiveEndReason' })
  reason!: LiveEndReason;
}

export class LiveChatMessageEvent {
  @ApiProperty({ enum: ['chatMessage'] })
  event!: 'chatMessage';

  @ApiProperty({ type: LiveChatMessageResponse })
  data!: LiveChatMessageResponse;
}

export class LiveChatMessageDeletedEvent {
  @ApiProperty({ enum: ['chatMessageDeleted'] })
  event!: 'chatMessageDeleted';

  @ApiProperty({ type: LiveChatMessageDeletedResponse })
  data!: LiveChatMessageDeletedResponse;
}

export class LiveHeartsEvent {
  @ApiProperty({ enum: ['hearts'] })
  event!: 'hearts';

  @ApiProperty({ type: LiveHeartsEventResponse })
  data!: LiveHeartsEventResponse;
}

export class LiveGiftEvent {
  @ApiProperty({ enum: ['gift'] })
  event!: 'gift';

  @ApiProperty({ type: LiveGiftEventResponse })
  data!: LiveGiftEventResponse;
}

export class LiveEndedEvent {
  @ApiProperty({ enum: ['liveEnded'] })
  event!: 'liveEnded';

  @ApiProperty({ type: LiveEndedEventResponse })
  data!: LiveEndedEventResponse;
}
