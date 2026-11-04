import { BadRequestException, Controller, Get, NotFoundException, Param, Query } from '@nestjs/common';
import { ApiBadRequestResponse, ApiNotFoundResponse, ApiOkResponse, ApiTags } from '@nestjs/swagger';
import type { VideoPageDto } from '@repo/shared';
import { ErrorResponse } from '../../../openapi/error.response';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { Public } from '../../auth/interfaces/public.decorator';
import { CollectionNotFoundError } from '../../collections/domain/collection.errors';
import { FeedService } from '../application/feed.service';
import { InvalidFeedCursorError } from '../domain/feed-cursor';
import { VideoGridQuery } from './feed.requests';
import { toFeedItemDto, VideoPageResponse } from './feed.responses';

// Vidéos d'une collection (ADR-072) : mêmes éléments que les grilles du profil, ouverts dans le même lecteur. La
// collection elle-même : `GET /collections/:id` (module collections).
@ApiTags('feed')
@Controller('collections')
export class CollectionVideosController {
  constructor(private readonly feed: FeedService) {}

  @Public()
  @Get(':id/videos')
  @ApiOkResponse({ type: VideoPageResponse, description: 'Vidéos de la collection, de la plus récemment ajoutée à la plus ancienne.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Curseur ou taille de page invalide.' })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Collection inconnue, ou privée et lue par un autre compte.' })
  async listCollectionVideos(
    @CurrentUser() user: AuthenticatedUser | undefined,
    @Param('id') id: string,
    @Query() query: VideoGridQuery,
  ): Promise<VideoPageDto> {
    try {
      const page = await this.feed.listCollectionVideos(id, query.cursor, query.limit, user?.userId ?? null);
      return { items: page.items.map(toFeedItemDto), nextCursor: page.nextCursor };
    } catch (error) {
      if (error instanceof InvalidFeedCursorError) throw new BadRequestException(error.message);
      if (error instanceof CollectionNotFoundError) throw new NotFoundException(error.message);
      throw error;
    }
  }
}
