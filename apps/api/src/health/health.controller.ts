import { Controller, Get } from '@nestjs/common';
import { ApiOkResponse, ApiTags } from '@nestjs/swagger';
import type { HealthDto } from '@repo/shared';
import { Public } from '../modules/auth/interfaces/public.decorator';
import { HealthResponse } from './health.response';

@ApiTags('health')
@Public()
@Controller('health')
export class HealthController {
  @Get()
  @ApiOkResponse({ type: HealthResponse })
  check(): HealthDto {
    return { status: 'ok', service: 'api', timestamp: new Date().toISOString() };
  }
}
