import { ApiProperty } from '@nestjs/swagger';
import { IsIn, Matches } from 'class-validator';
import { PUSH_TOKEN_PATTERN, type PushEnvironment } from '../domain/push';

const ENVIRONMENTS: PushEnvironment[] = ['sandbox', 'production'];

export class RegisterPushDeviceRequest {
  @ApiProperty({ description: 'Token APNs de l’appareil, en hexadécimal.', example: 'a1b2…' })
  @Matches(PUSH_TOKEN_PATTERN)
  token!: string;

  // `sandbox` pour un build de développement Xcode, `production` pour TestFlight et l'App Store.
  // Enum nommé sans description : elle produirait un `allOf` (voir CLAUDE.md).
  @ApiProperty({ enum: ENVIRONMENTS, enumName: 'PushEnvironment' })
  @IsIn(ENVIRONMENTS)
  environment!: PushEnvironment;
}
