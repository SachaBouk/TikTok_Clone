import { ApiProperty } from '@nestjs/swagger';
import type { HealthDto, HealthStatus } from '@repo/shared';

// Schéma OpenAPI de HealthDto : `implements` garantit à la compilation que la classe suit le type partagé.
export class HealthResponse implements HealthDto {
  @ApiProperty({ enum: ['ok', 'degraded'], enumName: 'HealthStatus' })
  status!: HealthStatus;

  @ApiProperty({ example: 'api' })
  service!: string;

  @ApiProperty({ format: 'date-time' })
  timestamp!: string;
}
