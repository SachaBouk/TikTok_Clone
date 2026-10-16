import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { AuthorStoryResponse } from '../../stories/interfaces/stories.responses';
import type { FeedItemDto, FeedPageDto, FeedViewerStateDto, VideoPageDto } from '@repo/shared';
import { toUserSummary, UserSummaryResponse } from '../../users/interfaces/user-summary.response';
import type { FeedItem } from '../application/feed.service';
import { VIDEO_VISIBILITIES, type VideoVisibility } from '../../videos/domain/video';

// Schémas OpenAPI des DTO partagés : `implements` garantit à la compilation que chaque classe suit son type.

export class FeedViewerStateResponse implements FeedViewerStateDto {
  @ApiProperty()
  liked!: boolean;

  @ApiProperty()
  favorited!: boolean;

  @ApiProperty()
  reposted!: boolean;

  @ApiProperty()
  followingAuthor!: boolean;
}

export class FeedItemResponse implements FeedItemDto {
  @ApiProperty({ format: 'uuid', description: 'Identifiant de la vidéo.' })
  id!: string;

  @ApiProperty({ type: String, nullable: true })
  description!: string | null;

  @ApiProperty({ format: 'uri', description: 'Manifeste HLS à donner à AVPlayer.' })
  hlsUrl!: string;

  @ApiProperty({ format: 'uri' })
  thumbnailUrl!: string;

  // Privée (ADR-061) : seul son auteur la reçoit.
  @ApiProperty({ enum: VIDEO_VISIBILITIES, enumName: 'VideoVisibility' })
  visibility!: VideoVisibility;

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;

  @ApiProperty({ type: 'integer', minimum: 0 })
  viewsCount!: number;

  @ApiProperty({ type: 'integer', minimum: 0 })
  likesCount!: number;

  @ApiProperty({ type: 'integer', minimum: 0 })
  commentsCount!: number;

  @ApiProperty({ type: 'integer', minimum: 0 })
  favoritesCount!: number;

  @ApiProperty({ type: 'integer', minimum: 0 })
  sharesCount!: number;

  @ApiProperty({ type: 'integer', minimum: 0 })
  repostsCount!: number;

  @ApiProperty({ type: UserSummaryResponse })
  author!: UserSummaryResponse;

  // État des boutons pour l'utilisateur connecté ; absent en mode invité. Pas de description :
  // elle forcerait un `allOf` autour de la référence, que le client Swift enveloppe dans une structure.
  @ApiPropertyOptional({ type: FeedViewerStateResponse })
  viewer?: FeedViewerStateResponse;

  @ApiPropertyOptional({ type: AuthorStoryResponse })
  authorStory?: AuthorStoryResponse;

  @ApiPropertyOptional({
    type: String,
    format: 'date-time',
    description: 'Historique de visionnage seulement (ADR-057) : dernière vue de la vidéo par le compte connecté.',
  })
  viewedAt?: string;
}

export class FeedPageResponse implements FeedPageDto {
  @ApiProperty({ type: [FeedItemResponse] })
  items!: FeedItemResponse[];

  @ApiProperty({
    type: String,
    nullable: true,
    description: 'À renvoyer tel quel pour la page suivante ; null à la fin du feed (repartir sans curseur pour un nouvel ordre).',
  })
  nextCursor!: string | null;
}

export class VideoPageResponse implements VideoPageDto {
  @ApiProperty({ type: [FeedItemResponse], description: 'De la plus récente à la plus ancienne.' })
  items!: FeedItemResponse[];

  @ApiProperty({ type: String, nullable: true, description: 'À renvoyer tel quel pour la page suivante ; null s’il n’y en a plus.' })
  nextCursor!: string | null;
}

// Mapping explicite, partagé par le feed et les grilles du profil : rien n'est exposé par accident (ADR-003).
export function toFeedItemDto({ video, author, viewer, authorStory, viewedAt }: FeedItem): FeedItemDto {
  return {
    id: video.id,
    description: video.description,
    hlsUrl: video.hlsUrl,
    thumbnailUrl: video.thumbnailUrl,
    visibility: video.visibility,
    createdAt: video.createdAt.toISOString(),
    viewsCount: video.viewsCount,
    likesCount: video.likesCount,
    commentsCount: video.commentsCount,
    favoritesCount: video.favoritesCount,
    sharesCount: video.sharesCount,
    repostsCount: video.repostsCount,
    author: toUserSummary(author),
    // Absent (pas null) en mode invité : voir FeedItemDto.
    ...(viewer && {
      viewer: {
        liked: viewer.liked,
        favorited: viewer.favorited,
        reposted: viewer.reposted,
        followingAuthor: viewer.followingAuthor,
      },
    }),
    ...(authorStory && { authorStory: { hasUnseen: authorStory.hasUnseen } }),
    ...(viewedAt && { viewedAt: viewedAt.toISOString() }),
  };
}
