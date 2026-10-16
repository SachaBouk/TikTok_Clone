import { BadRequestException, Controller, Get, NotFoundException, Param, Query } from '@nestjs/common';
import { ApiBadRequestResponse, ApiNotFoundResponse, ApiOkResponse, ApiTags, ApiUnauthorizedResponse } from '@nestjs/swagger';
import type { VideoPageDto } from '@repo/shared';
import { ErrorResponse } from '../../../openapi/error.response';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { Public } from '../../auth/interfaces/public.decorator';
import { UserNotFoundError } from '../../users/domain/user.errors';
import { FeedService, type FeedPage } from '../application/feed.service';
import { InvalidFeedCursorError } from '../domain/feed-cursor';
import { VideoGridQuery } from './feed.requests';
import { toFeedItemDto, VideoPageResponse } from './feed.responses';

const BAD_REQUEST = { type: ErrorResponse, description: 'Curseur ou taille de page invalide.' };
const USER_NOT_FOUND = { type: ErrorResponse, description: 'Pseudo inconnu.' };

// Grilles du profil (ADR-016). Mêmes éléments que le feed ; connecté, chaque vidéo porte l'état des boutons.
// Blocage : les vidéos des comptes bloqués (dans un sens ou dans l'autre) sont retirées, et leurs grilles sont vides.
// Les vidéos en traitement ou en échec de son propre compte : `GET /users/me/videos/pending` (module videos).
@ApiTags('feed')
@Controller('users')
export class ProfileVideosController {
  constructor(private readonly feed: FeedService) {}

  // Privés : seul le titulaire voit ses favoris.
  @Get('me/favorites')
  @ApiOkResponse({ type: VideoPageResponse, description: 'Favoris du compte connecté, du plus récent au plus ancien.' })
  @ApiBadRequestResponse(BAD_REQUEST)
  @ApiUnauthorizedResponse({ type: ErrorResponse, description: 'Access token absent, invalide ou expiré.' })
  listMyFavorites(@CurrentUser() user: AuthenticatedUser, @Query() query: VideoGridQuery): Promise<VideoPageDto> {
    return toPageDto(this.feed.listFavorites(user.userId, query.cursor, query.limit));
  }

  // Privées, comme les favoris.
  @Get('me/likes')
  @ApiOkResponse({ type: VideoPageResponse, description: 'Vidéos likées par le compte connecté, du like le plus récent au plus ancien.' })
  @ApiBadRequestResponse(BAD_REQUEST)
  @ApiUnauthorizedResponse({ type: ErrorResponse, description: 'Access token absent, invalide ou expiré.' })
  listMyLikes(@CurrentUser() user: AuthenticatedUser, @Query() query: VideoGridQuery): Promise<VideoPageDto> {
    return toPageDto(this.feed.listLikes(user.userId, query.cursor, query.limit));
  }

  // Vidéos privées (ADR-061) : grille « cadenas » de son seul profil.
  @Get('me/videos/private')
  @ApiOkResponse({ type: VideoPageResponse, description: 'Vidéos privées publiées du compte connecté, de la plus récente à la plus ancienne.' })
  @ApiBadRequestResponse(BAD_REQUEST)
  @ApiUnauthorizedResponse({ type: ErrorResponse, description: 'Access token absent, invalide ou expiré.' })
  listMyPrivateVideos(@CurrentUser() user: AuthenticatedUser, @Query() query: VideoGridQuery): Promise<VideoPageDto> {
    return toPageDto(this.feed.listPrivateVideos(user.userId, query.cursor, query.limit));
  }

  // Privé ; effacement : `DELETE /users/me/history` (module interactions).
  @Get('me/history')
  @ApiOkResponse({ type: VideoPageResponse, description: 'Historique de visionnage du compte connecté, du plus récent au plus ancien.' })
  @ApiBadRequestResponse(BAD_REQUEST)
  @ApiUnauthorizedResponse({ type: ErrorResponse, description: 'Access token absent, invalide ou expiré.' })
  listMyHistory(@CurrentUser() user: AuthenticatedUser, @Query() query: VideoGridQuery): Promise<VideoPageDto> {
    return toPageDto(this.feed.listHistory(user.userId, query.cursor, query.limit));
  }

  @Public()
  @Get(':username/videos')
  @ApiOkResponse({ type: VideoPageResponse, description: 'Vidéos publiées du compte, de la plus récente à la plus ancienne.' })
  @ApiBadRequestResponse(BAD_REQUEST)
  @ApiNotFoundResponse(USER_NOT_FOUND)
  listAccountVideos(
    @CurrentUser() user: AuthenticatedUser | undefined,
    @Param('username') username: string,
    @Query() query: VideoGridQuery,
  ): Promise<VideoPageDto> {
    return toPageDto(this.feed.listAuthorVideos(username, query.cursor, query.limit, user?.userId ?? null));
  }

  @Public()
  @Get(':username/reposts')
  @ApiOkResponse({ type: VideoPageResponse, description: 'Vidéos republiées par le compte, de la republication la plus récente à la plus ancienne.' })
  @ApiBadRequestResponse(BAD_REQUEST)
  @ApiNotFoundResponse(USER_NOT_FOUND)
  listReposts(
    @CurrentUser() user: AuthenticatedUser | undefined,
    @Param('username') username: string,
    @Query() query: VideoGridQuery,
  ): Promise<VideoPageDto> {
    return toPageDto(this.feed.listReposts(username, query.cursor, query.limit, user?.userId ?? null));
  }
}

async function toPageDto(pending: Promise<FeedPage>): Promise<VideoPageDto> {
  try {
    const page = await pending;
    return { items: page.items.map(toFeedItemDto), nextCursor: page.nextCursor };
  } catch (error) {
    if (error instanceof InvalidFeedCursorError) throw new BadRequestException(error.message);
    if (error instanceof UserNotFoundError) throw new NotFoundException(error.message);
    throw error;
  }
}
