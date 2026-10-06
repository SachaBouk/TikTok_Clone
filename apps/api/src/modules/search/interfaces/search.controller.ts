import { BadRequestException, Controller, Get, Param, Query } from '@nestjs/common';
import { ApiBadRequestResponse, ApiOkResponse, ApiTags } from '@nestjs/swagger';
import type { AccountSearchPageDto, HashtagDto, HashtagListDto } from '@repo/shared';
import { ErrorResponse } from '../../../openapi/error.response';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { Public } from '../../auth/interfaces/public.decorator';
import { InvalidHashtagError } from '../../videos/domain/video.errors';
import { SearchService } from '../application/search.service';
import { InvalidSearchCursorError } from '../domain/search-rules';
import { AccountSearchQuery, HashtagSearchQuery } from './search.requests';
import { AccountSearchPageResponse, HashtagListResponse, HashtagResponse, toAccountSearchItemDto, toHashtagDto } from './search.responses';

// Recherche (ADR-049) : publique, invité compris. Connecté, les comptes bloqués (dans un sens ou dans l'autre) sont
// exclus et chaque compte trouvé porte sa relation avec le compte connecté.
@ApiTags('search')
@Controller('search')
export class SearchController {
  constructor(private readonly search: SearchService) {}

  @Public()
  @Get('users')
  @ApiOkResponse({
    type: AccountSearchPageResponse,
    description:
      'Comptes dont le pseudo ou le nom contient `q`, sans tenir compte de la casse : pseudo identique, pseudo qui commence par `q`, ' +
      'puis abonnés décroissants. 100 résultats au plus. Comptes suspendus exclus ; connecté, comptes bloqués exclus.',
  })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Texte, curseur ou taille de page invalide.' })
  async searchUsers(@CurrentUser() user: AuthenticatedUser | undefined, @Query() query: AccountSearchQuery): Promise<AccountSearchPageDto> {
    try {
      const page = await this.search.searchAccounts(query.q, user?.userId ?? null, query.cursor, query.limit);
      return { items: page.items.map(toAccountSearchItemDto), nextCursor: page.nextCursor };
    } catch (error) {
      if (error instanceof InvalidSearchCursorError) throw new BadRequestException(error.message);
      throw error;
    }
  }

  @Public()
  @Get('hashtags')
  @ApiOkResponse({
    type: HashtagListResponse,
    description: 'Hashtags qui commencent par `q` (« # » initial ignoré) et ont au moins une vidéo, du plus utilisé au moins utilisé.',
  })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Texte ou nombre invalide.' })
  async searchHashtags(@Query() query: HashtagSearchQuery): Promise<HashtagListDto> {
    return { items: (await this.search.searchHashtags(query.q, query.limit)).map(toHashtagDto) };
  }

  @Public()
  @Get('trending-hashtags')
  @ApiOkResponse({
    type: HashtagListResponse,
    description: 'Hashtags tendance, 10 au plus : vidéos publiées ces 7 derniers jours, puis nombre total de vidéos.',
  })
  async listTrendingHashtags(): Promise<HashtagListDto> {
    return { items: (await this.search.trendingHashtags()).map(toHashtagDto) };
  }
}

// Page d'un hashtag (ADR-049) ; ses vidéos : `GET /hashtags/:name/videos` (module feed).
@ApiTags('search')
@Controller('hashtags')
export class HashtagsController {
  constructor(private readonly search: SearchService) {}

  @Public()
  @Get(':name')
  @ApiOkResponse({ type: HashtagResponse, description: 'Un nom valide inconnu a 0 vidéo.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Nom de hashtag invalide.' })
  async getHashtag(@Param('name') name: string): Promise<HashtagDto> {
    try {
      return toHashtagDto(await this.search.getHashtag(name));
    } catch (error) {
      if (error instanceof InvalidHashtagError) throw new BadRequestException(error.message);
      throw error;
    }
  }
}
