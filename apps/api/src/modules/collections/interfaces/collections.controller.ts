import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Query, UseFilters } from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiConflictResponse,
  ApiCreatedResponse,
  ApiForbiddenResponse,
  ApiNoContentResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import type { CollectionDto, CollectionListDto } from '@repo/shared';
import { ErrorResponse } from '../../../openapi/error.response';
import { ApiTooManyRequests } from '../../../rate-limit/api-too-many-requests.decorator';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { Public } from '../../auth/interfaces/public.decorator';
import { InteractionErrorFilter } from '../../interactions/interfaces/interaction-error.filter';
import { UserErrorFilter } from '../../users/interfaces/user-error.filter';
import { CollectionsService } from '../application/collections.service';
import { CollectionErrorFilter } from './collection-error.filter';
import {
  CollectionVideosRequest,
  CreateCollectionRequest,
  MyCollectionsQuery,
  RemoveCollectionVideosQuery,
  UpdateCollectionRequest,
} from './collections.requests';
import { CollectionListResponse, CollectionResponse, toCollectionDto } from './collections.responses';

const UNAUTHORIZED = { type: ErrorResponse, description: 'Access token absent, invalide ou expiré.' };
const NOT_FOUND = { type: ErrorResponse, description: 'Collection inconnue, à un autre compte, ou privée.' };

// Collections de favoris (ADR-072). Vidéos d'une collection : `GET /collections/:id/videos` (module feed).
// Les erreurs des modules interactions (favori impossible) et users (pseudo inconnu) gardent leurs codes.
@ApiTags('collections')
@UseFilters(CollectionErrorFilter, InteractionErrorFilter, UserErrorFilter)
@Controller()
export class CollectionsController {
  constructor(private readonly collections: CollectionsService) {}

  @Get('users/me/collections')
  @ApiOkResponse({ type: CollectionListResponse, description: 'Ses collections, de la plus récemment utilisée à la plus ancienne.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Identifiant de vidéo invalide.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async listMyCollections(@CurrentUser() user: AuthenticatedUser, @Query() query: MyCollectionsQuery): Promise<CollectionListDto> {
    return { items: (await this.collections.listMine(user.userId, query.videoId)).map(toCollectionDto) };
  }

  // Ses collections publiques, visibles même si ses favoris sont privés ; toutes pour son titulaire.
  @Public()
  @Get('users/:username/collections')
  @ApiOkResponse({ type: CollectionListResponse, description: 'Collections publiques du compte.' })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Pseudo inconnu.' })
  async listProfileCollections(@CurrentUser() user: AuthenticatedUser | undefined, @Param('username') username: string): Promise<CollectionListDto> {
    return { items: (await this.collections.listForProfile(username, user?.userId ?? null)).map(toCollectionDto) };
  }

  @Post('collections')
  @ApiCreatedResponse({ type: CollectionResponse })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Nom invalide, trop de vidéos.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiForbiddenResponse({ type: ErrorResponse, description: 'Vidéo d’un compte bloqué.' })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Vidéo indisponible.' })
  @ApiConflictResponse({ type: ErrorResponse, description: '100 collections au plus.' })
  @ApiTooManyRequests('Trop de favoris ajoutés.')
  async createCollection(@CurrentUser() user: AuthenticatedUser, @Body() body: CreateCollectionRequest): Promise<CollectionDto> {
    return toCollectionDto(await this.collections.create(user.userId, { name: body.name, visibility: body.visibility, videoIds: body.videoIds }));
  }

  @Public()
  @Get('collections/:id')
  @ApiOkResponse({ type: CollectionResponse })
  @ApiNotFoundResponse(NOT_FOUND)
  async getCollection(@CurrentUser() user: AuthenticatedUser | undefined, @Param('id') id: string): Promise<CollectionDto> {
    return toCollectionDto(await this.collections.get(id, user?.userId ?? null));
  }

  @Patch('collections/:id')
  @ApiOkResponse({ type: CollectionResponse })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Nom invalide.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(NOT_FOUND)
  async updateCollection(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
    @Body() body: UpdateCollectionRequest,
  ): Promise<CollectionDto> {
    return toCollectionDto(await this.collections.update(user.userId, id, { name: body.name, visibility: body.visibility }));
  }

  // Les vidéos restent en favoris.
  @Delete('collections/:id')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Collection supprimée.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(NOT_FOUND)
  async deleteCollection(@CurrentUser() user: AuthenticatedUser, @Param('id') id: string): Promise<void> {
    await this.collections.delete(user.userId, id);
  }

  // Mises en favori si besoin ; déjà présentes : ignorées.
  @Post('collections/:id/videos')
  @HttpCode(200)
  @ApiOkResponse({ type: CollectionResponse })
  @ApiBadRequestResponse({ type: ErrorResponse, description: '1 à 50 vidéos.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiForbiddenResponse({ type: ErrorResponse, description: 'Vidéo d’un compte bloqué.' })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Collection ou vidéo indisponible.' })
  @ApiTooManyRequests('Trop de favoris ajoutés.')
  async addCollectionVideos(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
    @Body() body: CollectionVideosRequest,
  ): Promise<CollectionDto> {
    return toCollectionDto(await this.collections.addVideos(user.userId, id, body.videoIds));
  }

  // Retirées de la collection, gardées en favoris.
  @Delete('collections/:id/videos')
  @ApiOkResponse({ type: CollectionResponse })
  @ApiBadRequestResponse({ type: ErrorResponse, description: '1 à 50 vidéos.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(NOT_FOUND)
  async removeCollectionVideos(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
    @Query() query: RemoveCollectionVideosQuery,
  ): Promise<CollectionDto> {
    return toCollectionDto(await this.collections.removeVideos(user.userId, id, query.videoIds));
  }
}
