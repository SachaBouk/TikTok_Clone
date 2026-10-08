import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post, Put, Query, UseFilters } from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiConflictResponse,
  ApiCreatedResponse,
  ApiNoContentResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import type { StoryDto, StoryTrayDto, StoryUploadDto, StoryViewersPageDto, UserStoriesDto } from '@repo/shared';
import { ErrorResponse } from '../../../openapi/error.response';
import { ApiTooManyRequests } from '../../../rate-limit/api-too-many-requests.decorator';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { Public } from '../../auth/interfaces/public.decorator';
import { CompleteUploadRequest } from '../../videos/interfaces/videos.requests';
import { StoriesService } from '../application/stories.service';
import { CreateStoryUploadRequest, StoryViewersQuery } from './stories.requests';
import {
  StoryResponse,
  StoryTrayResponse,
  StoryUploadResponse,
  StoryViewersPageResponse,
  toStoryDto,
  toStoryTrayDto,
  toStoryUploadDto,
  toStoryViewersPageDto,
  toUserStoriesDto,
  UserStoriesResponse,
} from './stories.responses';
import { StoryErrorFilter } from './story-error.filter';

const UNAUTHORIZED = { type: ErrorResponse, description: 'Access token absent, invalide ou expiré.' };
const NOT_FOUND = { type: ErrorResponse, description: 'Story inconnue, expirée, ou d’un compte masqué (suspendu, blocage).' };

// Stories (ADR-051) : vidéo (60 s) ou photo, visibles 24 h après leur publication. Publiques ; publier, voir, aimer et
// la rangée demandent un compte.
@ApiTags('stories')
@UseFilters(StoryErrorFilter)
@Controller('stories')
export class StoriesController {
  constructor(private readonly stories: StoriesService) {}

  @Post('upload-url')
  @ApiCreatedResponse({
    type: StoryUploadResponse,
    description:
      'Story créée en `uploading`. Envoyer chaque partie (`partSize` octets, la dernière plus petite) en PUT sur son URL, ' +
      'garder les en-têtes `ETag`, puis appeler `completeStoryUpload`.',
  })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Format non pris en charge ou fichier trop volumineux.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiConflictResponse({ type: ErrorResponse, description: '30 stories actives au plus.' })
  @ApiTooManyRequests('Trop de stories publiées récemment (une story vidéo compte dans la limite des vidéos)')
  async createStoryUpload(@CurrentUser() user: AuthenticatedUser, @Body() body: CreateStoryUploadRequest): Promise<StoryUploadDto> {
    return toStoryUploadDto(await this.stories.createUpload(user.userId, body));
  }

  @Patch(':id/uploaded')
  @HttpCode(200)
  @ApiOkResponse({ type: StoryResponse, description: 'Photo publiée (`ready`), ou vidéo en `processing` (transcodage lancé).' })
  @ApiBadRequestResponse({
    type: ErrorResponse,
    description: 'Parties manquantes ou ETags incorrects (renvoyer les parties), ou photo refusée (JPEG 9:16 attendu, story en échec).',
  })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Story inconnue ou appartenant à un autre compte.' })
  @ApiConflictResponse({ type: ErrorResponse, description: 'Envoi déjà confirmé.' })
  async completeStoryUpload(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) id: string,
    @Body() body: CompleteUploadRequest,
  ): Promise<StoryDto> {
    return toStoryDto(await this.stories.completeUpload(user.userId, id, body.parts));
  }

  @Get('feed')
  @ApiOkResponse({ type: StoryTrayResponse })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async getStoryTray(@CurrentUser() user: AuthenticatedUser): Promise<StoryTrayDto> {
    return toStoryTrayDto(await this.stories.getTray(user.userId));
  }

  // Public (mode invité) pour une story visible ; l'auteur, connecté, voit aussi ses stories en cours de traitement.
  @Public()
  @Get(':id')
  @ApiOkResponse({ type: StoryResponse })
  @ApiNotFoundResponse(NOT_FOUND)
  async getStory(@CurrentUser() user: AuthenticatedUser | undefined, @Param('id', new ParseUUIDPipe()) id: string): Promise<StoryDto> {
    return toStoryDto(await this.stories.getStory(id, user?.userId ?? null));
  }

  // Par son auteur, quel que soit le statut ; vues et likes disparaissent avec elle, ses fichiers peu après.
  @Delete(':id')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Story supprimée.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Story inconnue, déjà supprimée ou expirée, ou appartenant à un autre compte.' })
  async deleteStory(@CurrentUser() user: AuthenticatedUser, @Param('id', new ParseUUIDPipe()) id: string): Promise<void> {
    await this.stories.deleteStory(user.userId, id);
  }

  // À l'affichage d'une story dans la visionneuse. Sa propre story n'est pas comptée ; au-delà de la limite, ignorée.
  @Post(':id/view')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Vue enregistrée (ou ignorée).' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(NOT_FOUND)
  async viewStory(@CurrentUser() user: AuthenticatedUser, @Param('id', new ParseUUIDPipe()) id: string): Promise<void> {
    await this.stories.recordView(user.userId, id);
  }

  @Put(':id/like')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Story aimée (vaut vue). Idempotent.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Sa propre story.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(NOT_FOUND)
  @ApiTooManyRequests('Trop de likes récemment (ADR-039)')
  async likeStory(@CurrentUser() user: AuthenticatedUser, @Param('id', new ParseUUIDPipe()) id: string): Promise<void> {
    await this.stories.setLiked(user.userId, id, true);
  }

  @Delete(':id/like')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Like retiré. Idempotent.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Sa propre story.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(NOT_FOUND)
  async unlikeStory(@CurrentUser() user: AuthenticatedUser, @Param('id', new ParseUUIDPipe()) id: string): Promise<void> {
    await this.stories.setLiked(user.userId, id, false);
  }

  @Get(':id/viewers')
  @ApiOkResponse({ type: StoryViewersPageResponse, description: 'Comptes qui l’ont vue, du plus récent au plus ancien, avec les chiffres.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Curseur invalide.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Story inconnue, expirée, ou d’un autre compte (réservé à l’auteur).' })
  async listStoryViewers(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) id: string,
    @Query() query: StoryViewersQuery,
  ): Promise<StoryViewersPageDto> {
    return toStoryViewersPageDto(await this.stories.listViewers(user.userId, id, query.cursor, query.limit));
  }
}

@ApiTags('stories')
@UseFilters(StoryErrorFilter)
@Controller('users')
export class UserStoriesController {
  constructor(private readonly stories: StoriesService) {}

  // Public : stories actives du compte (aucune s'il est masqué au lecteur), avec l'état du lecteur ou les chiffres de
  // l'auteur.
  @Public()
  @Get(':username/stories')
  @ApiOkResponse({ type: UserStoriesResponse })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Compte inconnu.' })
  async listUserStories(@CurrentUser() user: AuthenticatedUser | undefined, @Param('username') username: string): Promise<UserStoriesDto> {
    return toUserStoriesDto(await this.stories.listUserStories(username, user?.userId ?? null));
  }
}
