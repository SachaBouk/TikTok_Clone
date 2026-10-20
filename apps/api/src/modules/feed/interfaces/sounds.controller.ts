import { BadRequestException, Controller, Delete, Get, HttpCode, NotFoundException, Param, ParseUUIDPipe, Put, Query } from '@nestjs/common';
import { ApiBadRequestResponse, ApiNoContentResponse, ApiNotFoundResponse, ApiOkResponse, ApiTags, ApiUnauthorizedResponse } from '@nestjs/swagger';
import type { SoundListDto, SoundPageDto } from '@repo/shared';
import { ErrorResponse } from '../../../openapi/error.response';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { SoundNotFoundError } from '../../videos/domain/video.errors';
import { FeedService, type SoundList, type SoundPage } from '../application/feed.service';
import { InvalidFeedCursorError } from '../domain/feed-cursor';
import { SoundIdsQuery, SoundPageQuery, SoundSearchQuery } from './sounds.requests';
import { SoundListResponse, SoundPageResponse, toSoundDto } from './sounds.responses';

const UNAUTHORIZED = { type: ErrorResponse, description: 'Access token absent, invalide ou expiré.' };

// Sons repris des vidéos publiées (ADR-064), pour l'éditeur de l'app : compte connecté. Seuls les sons d'une vidéo
// publique, publiée, qui le permet, et d'un auteur non masqué (suspendu, blocage) sont proposés.
@ApiTags('sounds')
@Controller('sounds')
export class SoundsController {
  constructor(private readonly feed: FeedService) {}

  @Get('recommended')
  @ApiOkResponse({ type: SoundPageResponse, description: 'Les plus utilisés, puis les plus récents ; 200 au plus.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Curseur ou taille de page invalide.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  listRecommendedSounds(@CurrentUser() user: AuthenticatedUser, @Query() query: SoundPageQuery): Promise<SoundPageDto> {
    return this.list(user, 'recommended', query);
  }

  @Get('favorites')
  @ApiOkResponse({ type: SoundPageResponse, description: 'Sons favoris, du plus récemment ajouté au plus ancien.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Curseur ou taille de page invalide.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  listFavoriteSounds(@CurrentUser() user: AuthenticatedUser, @Query() query: SoundPageQuery): Promise<SoundPageDto> {
    return this.list(user, 'favorites', query);
  }

  @Get('search')
  @ApiOkResponse({ type: SoundPageResponse, description: 'Pseudo, nom ou description de la vidéo d’origine ; 200 au plus.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Texte, curseur ou taille de page invalide.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async searchSounds(@CurrentUser() user: AuthenticatedUser, @Query() query: SoundSearchQuery): Promise<SoundPageDto> {
    return toPage(await this.cursorErrors(() => this.feed.searchSounds(user.userId, query.q.trim(), query.cursor, query.limit)));
  }

  // Déclarée après les listes nommées : `recommended` ou `favorites` ne sont pas des identifiants.
  @Get()
  @ApiOkResponse({ type: SoundListResponse, description: 'Sons demandés, dans l’ordre ; un son qui n’est plus proposé est omis.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Identifiants invalides (1 à 50).' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async getSounds(@CurrentUser() user: AuthenticatedUser, @Query() query: SoundIdsQuery): Promise<SoundListDto> {
    return { items: (await this.feed.getSounds(user.userId, query.ids)).map(toSoundDto) };
  }

  @Put(':id/favorite')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Son ajouté aux favoris (idempotent).' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Son introuvable ou plus proposé.' })
  async favoriteSound(@CurrentUser() user: AuthenticatedUser, @Param('id', new ParseUUIDPipe()) id: string): Promise<void> {
    try {
      await this.feed.setSoundFavorite(user.userId, id, true);
    } catch (error) {
      if (error instanceof SoundNotFoundError) throw new NotFoundException(error.message);
      throw error;
    }
  }

  @Delete(':id/favorite')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Son retiré des favoris (idempotent).' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async unfavoriteSound(@CurrentUser() user: AuthenticatedUser, @Param('id', new ParseUUIDPipe()) id: string): Promise<void> {
    await this.feed.setSoundFavorite(user.userId, id, false);
  }

  private async list(user: AuthenticatedUser, list: SoundList, query: SoundPageQuery): Promise<SoundPageDto> {
    return toPage(await this.cursorErrors(() => this.feed.listSounds(user.userId, list, query.cursor, query.limit)));
  }

  private async cursorErrors(load: () => Promise<SoundPage>): Promise<SoundPage> {
    try {
      return await load();
    } catch (error) {
      if (error instanceof InvalidFeedCursorError) throw new BadRequestException(error.message);
      throw error;
    }
  }
}

function toPage(page: SoundPage): SoundPageDto {
  return { items: page.items.map(toSoundDto), nextCursor: page.nextCursor };
}
