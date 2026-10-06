import { BadRequestException, Controller, Get, Param, Query } from '@nestjs/common';
import { ApiBadRequestResponse, ApiOkResponse, ApiTags } from '@nestjs/swagger';
import type { VideoPageDto } from '@repo/shared';
import { ErrorResponse } from '../../../openapi/error.response';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { Public } from '../../auth/interfaces/public.decorator';
import { InvalidHashtagError } from '../../videos/domain/video.errors';
import { FeedService } from '../application/feed.service';
import { InvalidFeedCursorError } from '../domain/feed-cursor';
import { VideoGridQuery } from './feed.requests';
import { toFeedItemDto, VideoPageResponse } from './feed.responses';

// Grille d'un hashtag (ADR-049) : mêmes éléments que le feed et les grilles du profil, ouverts dans le même lecteur.
// Le nom et le nombre de vidéos : `GET /hashtags/:name` (module search).
@ApiTags('feed')
@Controller('hashtags')
export class HashtagVideosController {
  constructor(private readonly feed: FeedService) {}

  @Public()
  @Get(':name/videos')
  @ApiOkResponse({
    type: VideoPageResponse,
    description: 'Vidéos publiées du hashtag, de la plus récemment publiée à la plus ancienne. Comptes masqués retirés (page plus courte).',
  })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Nom de hashtag, curseur ou taille de page invalide.' })
  async listHashtagVideos(
    @CurrentUser() user: AuthenticatedUser | undefined,
    @Param('name') name: string,
    @Query() query: VideoGridQuery,
  ): Promise<VideoPageDto> {
    try {
      const page = await this.feed.listHashtagVideos(name, query.cursor, query.limit, user?.userId ?? null);
      return { items: page.items.map(toFeedItemDto), nextCursor: page.nextCursor };
    } catch (error) {
      if (error instanceof InvalidFeedCursorError || error instanceof InvalidHashtagError) throw new BadRequestException(error.message);
      throw error;
    }
  }
}
