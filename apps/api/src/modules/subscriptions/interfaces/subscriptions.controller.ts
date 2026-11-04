import { Controller, Get } from '@nestjs/common';
import { ApiOkResponse, ApiTags, ApiUnauthorizedResponse } from '@nestjs/swagger';
import type { PlusStatusDto } from '@repo/shared';
import { ErrorResponse } from '../../../openapi/error.response';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { SubscriptionsService } from '../application/subscriptions.service';
import { PlusStatusResponse, toPlusStatusDto } from './subscriptions.responses';

// Abonnement « Plus » (ADR-073). L'achat passe par le SDK RevenueCat de l'app ; l'état arrive par le webhook.
@ApiTags('subscriptions')
@Controller()
export class SubscriptionsController {
  constructor(private readonly subscriptions: SubscriptionsService) {}

  @Get('users/me/plus')
  @ApiOkResponse({ type: PlusStatusResponse })
  @ApiUnauthorizedResponse({ type: ErrorResponse, description: 'Access token absent, invalide ou expiré.' })
  async getMyPlusStatus(@CurrentUser() user: AuthenticatedUser): Promise<PlusStatusDto> {
    return toPlusStatusDto(await this.subscriptions.getStatus(user.userId));
  }
}
