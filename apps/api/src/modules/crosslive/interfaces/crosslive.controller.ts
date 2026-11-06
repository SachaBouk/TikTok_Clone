import { Controller, HttpCode, NotFoundException, Post, ServiceUnavailableException } from '@nestjs/common';
import { ApiNotFoundResponse, ApiOkResponse, ApiServiceUnavailableResponse, ApiTags, ApiUnauthorizedResponse } from '@nestjs/swagger';
import type { LiveParticipantTokenDto } from '@repo/shared';
import { ErrorResponse } from '../../../openapi/error.response';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { CrossLiveService } from '../application/crosslive.service';
import { CrossLiveUnavailableError, ParticipantNotFoundError } from '../domain/participant-token';
import { LiveParticipantTokenResponse } from './crosslive.responses';

// Live commun d'echimine (ADR-079) : jeton de participant du compte connecté, demandé par le SDK à chaque connexion.
@ApiTags('live')
@Controller('live')
export class CrossLiveController {
  constructor(private readonly crossLive: CrossLiveService) {}

  @Post('participant-token')
  @HttpCode(200)
  @ApiOkResponse({ type: LiveParticipantTokenResponse, description: 'Jeton frais à chaque appel, jamais mis en cache.' })
  @ApiUnauthorizedResponse({ type: ErrorResponse, description: 'Compte non connecté.' })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Compte introuvable.' })
  @ApiServiceUnavailableResponse({ type: ErrorResponse, description: 'Secret de l’App membre non configuré : Live indisponible.' })
  async createLiveParticipantToken(@CurrentUser() user: AuthenticatedUser): Promise<LiveParticipantTokenDto> {
    try {
      return { token: await this.crossLive.participantToken(user.userId) };
    } catch (error) {
      if (error instanceof CrossLiveUnavailableError) throw new ServiceUnavailableException(error.message);
      if (error instanceof ParticipantNotFoundError) throw new NotFoundException(error.message);
      throw error;
    }
  }
}
