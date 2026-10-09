import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsInt, IsOptional, IsString, Max, MaxLength, Min, MinLength } from 'class-validator';
import { MAX_HEARTS_PER_BATCH, MAX_LIVE_MESSAGE_LENGTH, MAX_LIVE_TITLE_LENGTH } from '../domain/live';

export class StartLiveRequest {
  @ApiPropertyOptional({ maxLength: MAX_LIVE_TITLE_LENGTH, description: 'Titre facultatif, nettoyé ; vide = sans titre.' })
  @IsOptional()
  @IsString()
  @MaxLength(MAX_LIVE_TITLE_LENGTH + 20)
  title?: string;
}

export class SendLiveMessageRequest {
  @ApiProperty({ minLength: 1, maxLength: MAX_LIVE_MESSAGE_LENGTH, description: 'Texte nettoyé (espaces de bord retirés).' })
  @IsString()
  @MinLength(1)
  @MaxLength(MAX_LIVE_MESSAGE_LENGTH + 20)
  content!: string;
}

export class SendLiveHeartsRequest {
  @ApiProperty({ type: 'integer', minimum: 1, maximum: MAX_HEARTS_PER_BATCH, description: 'Cœurs de ce lot (touchers regroupés par l’app).' })
  @IsInt()
  @Min(1)
  @Max(MAX_HEARTS_PER_BATCH)
  count!: number;
}
