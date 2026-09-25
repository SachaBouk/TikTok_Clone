import { Body, Controller, Delete, HttpCode, Param, Put } from '@nestjs/common';
import { ApiBadRequestResponse, ApiNoContentResponse, ApiTags, ApiUnauthorizedResponse } from '@nestjs/swagger';
import { ErrorResponse } from '../../../openapi/error.response';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { PushService } from '../application/push.service';
import { RegisterPushDeviceRequest } from './push.requests';

const UNAUTHORIZED = { type: ErrorResponse, description: 'Access token absent, invalide ou expiré.' };

// Appareils qui reçoivent les notifications push du compte connecté (APNs).
@ApiTags('push')
@Controller('push/devices')
export class PushController {
  constructor(private readonly push: PushService) {}

  // À chaque lancement de l'app (le token peut changer) et après chaque connexion. Idempotent ;
  // un token déjà enregistré pour un autre compte passe à celui-ci.
  @Put()
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Appareil enregistré.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Token ou environnement invalide.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async registerPushDevice(@CurrentUser() user: AuthenticatedUser, @Body() body: RegisterPushDeviceRequest): Promise<void> {
    await this.push.registerDevice(user.userId, body.token, body.environment);
  }

  // À la déconnexion, avant de jeter les tokens de session. Sans effet pour le token d'un autre compte.
  @Delete(':token')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Appareil retiré.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async unregisterPushDevice(@CurrentUser() user: AuthenticatedUser, @Param('token') token: string): Promise<void> {
    await this.push.unregisterDevice(user.userId, token);
  }
}
