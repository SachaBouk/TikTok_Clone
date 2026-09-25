import { BadRequestException, Controller, Get, NotFoundException, Param, ParseUUIDPipe, Query } from '@nestjs/common';
import { ApiBadRequestResponse, ApiNotFoundResponse, ApiOkResponse, ApiTags } from '@nestjs/swagger';
import type { FeedItemDto, FeedPageDto } from '@repo/shared';
import { ErrorResponse } from '../../../openapi/error.response';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { Public } from '../../auth/interfaces/public.decorator';
import { FeedService } from '../application/feed.service';
import { InvalidFeedCursorError } from '../domain/feed-cursor';
import { FeedItemNotFoundError } from '../domain/feed.errors';
import { FeedQuery } from './feed.requests';
import { FeedItemResponse, FeedPageResponse, toFeedItemDto } from './feed.responses';

@ApiTags('feed')
@Controller('feed')
export class FeedController {
  constructor(private readonly feed: FeedService) {}

  // Mode invité (ADR-010) : le feed est lisible sans compte. Connecté, chaque vidéo porte l'état des boutons.
  @Public()
  @Get()
  @ApiOkResponse({
    type: FeedPageResponse,
    description:
      'Vidéos publiées, dans un ordre aléatoire propre à la session. Sans `cursor` : nouvelle session. ' +
      'Avec le `nextCursor` reçu : page suivante, sans doublon. Une session de plus de 2 h repart sur un nouvel ordre.',
  })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Curseur ou taille de page invalide.' })
  async getFeed(@CurrentUser() user: AuthenticatedUser | undefined, @Query() query: FeedQuery): Promise<FeedPageDto> {
    try {
      const page = await this.feed.getPage(query.cursor, query.limit, user?.userId ?? null);
      return { items: page.items.map(toFeedItemDto), nextCursor: page.nextCursor };
    } catch (error) {
      if (error instanceof InvalidFeedCursorError) throw new BadRequestException(error.message);
      throw error;
    }
  }

  // Une vidéo seule, au format du feed (compteurs, auteur, état des boutons) : pour l'ouvrir dans le lecteur
  // depuis une notification, l'historique des commentaires ou un message partagé. `GET /videos/:id` ne donne
  // que son état de traitement et ses URLs.
  @Public()
  @Get('items/:id')
  @ApiOkResponse({ type: FeedItemResponse })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Identifiant invalide.' })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Vidéo inconnue, supprimée ou pas encore publiée.' })
  async getFeedItem(
    @CurrentUser() user: AuthenticatedUser | undefined,
    @Param('id', new ParseUUIDPipe()) id: string,
  ): Promise<FeedItemDto> {
    try {
      return toFeedItemDto(await this.feed.getItem(id, user?.userId ?? null));
    } catch (error) {
      if (error instanceof FeedItemNotFoundError) throw new NotFoundException(error.message);
      throw error;
    }
  }
}
