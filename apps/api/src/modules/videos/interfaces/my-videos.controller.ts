import { Controller, Get } from '@nestjs/common';
import { ApiOkResponse, ApiTags, ApiUnauthorizedResponse } from '@nestjs/swagger';
import type { PendingVideosDto } from '@repo/shared';
import { ErrorResponse } from '../../../openapi/error.response';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { VideosService } from '../application/videos.service';
import { PendingVideosResponse, toVideoDto } from './videos.responses';

// Vidéos du compte connecté qui ne sont visibles que de lui. Les vidéos publiées d'un compte sont
// servies par le module feed (`GET /users/:username/videos`), avec les auteurs et l'état du lecteur.
@ApiTags('videos')
@Controller('users/me/videos')
export class MyVideosController {
  constructor(private readonly videos: VideosService) {}

  // En tête de sa grille : « en cours de publication » ou « échec ». Suivre ensuite l'événement `videoProcessed`.
  @Get('pending')
  @ApiOkResponse({ type: PendingVideosResponse })
  @ApiUnauthorizedResponse({ type: ErrorResponse, description: 'Access token absent, invalide ou expiré.' })
  async listMyPendingVideos(@CurrentUser() user: AuthenticatedUser): Promise<PendingVideosDto> {
    return { items: (await this.videos.listUnpublishedVideos(user.userId)).map(toVideoDto) };
  }
}
