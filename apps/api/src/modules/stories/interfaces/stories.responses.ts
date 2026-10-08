import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import type {
  AuthorStoryDto,
  MessageStoryDto,
  StoryDto,
  StoryItemDto,
  StoryMediaType,
  StoryStatsDto,
  StoryStatus,
  StoryTrayDto,
  StoryTrayItemDto,
  StoryUploadDto,
  StoryViewerDto,
  StoryViewerStateDto,
  StoryViewersPageDto,
  UserStoriesDto,
} from '@repo/shared';
import { toUserSummary, UserSummaryResponse } from '../../users/interfaces/user-summary.response';
import { UploadPartUrlResponse } from '../../videos/interfaces/videos.responses';
import type { StoryItem, StoryTrayEntry, StoryUpload, StoryViewerEntry, StoryViewersPage, UserStories } from '../application/stories.service';
import type { ActiveStory, Story } from '../domain/story';

// Schémas OpenAPI des DTO partagés : `implements` garantit à la compilation que chaque classe suit son type.

export class StoryResponse implements StoryDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty({ format: 'uuid', description: 'Auteur de la story.' })
  userId!: string;

  @ApiProperty({ enum: ['video', 'photo'], enumName: 'StoryMediaType' })
  mediaType!: StoryMediaType;

  @ApiProperty({ enum: ['uploading', 'processing', 'ready', 'failed'], enumName: 'StoryStatus' })
  status!: StoryStatus;

  @ApiProperty({ type: String, nullable: true, format: 'uri', description: 'Manifeste HLS (vidéo) ou photo JPEG, quand la story est `ready`.' })
  mediaUrl!: string | null;

  @ApiProperty({ type: String, nullable: true, format: 'uri' })
  thumbnailUrl!: string | null;

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;

  @ApiProperty({ type: String, nullable: true, format: 'date-time', description: 'Publication (`ready`).' })
  publishedAt!: string | null;

  @ApiProperty({ type: String, nullable: true, format: 'date-time', description: 'Fin de visibilité, 24 h après la publication.' })
  expiresAt!: string | null;
}

export class StoryUploadResponse implements StoryUploadDto {
  @ApiProperty({ type: StoryResponse })
  story!: StoryResponse;

  @ApiProperty({ type: 'integer', description: 'Taille de chaque partie en octets ; la dernière peut être plus petite.' })
  partSize!: number;

  @ApiProperty({ type: [UploadPartUrlResponse] })
  parts!: UploadPartUrlResponse[];

  @ApiProperty({ format: 'date-time', description: 'Expiration des URLs signées.' })
  expiresAt!: string;
}

export class StoryViewerStateResponse implements StoryViewerStateDto {
  @ApiProperty()
  viewed!: boolean;

  @ApiProperty()
  liked!: boolean;
}

export class StoryStatsResponse implements StoryStatsDto {
  @ApiProperty({ type: 'integer', minimum: 0 })
  viewersCount!: number;

  @ApiProperty({ type: 'integer', minimum: 0 })
  likesCount!: number;
}

export class StoryItemResponse extends StoryResponse implements StoryItemDto {
  @ApiPropertyOptional({ type: StoryViewerStateResponse })
  viewer?: StoryViewerStateResponse;

  @ApiPropertyOptional({ type: StoryStatsResponse })
  stats?: StoryStatsResponse;
}

export class UserStoriesResponse implements UserStoriesDto {
  @ApiProperty({ type: UserSummaryResponse })
  user!: UserSummaryResponse;

  @ApiProperty({ type: [StoryItemResponse], description: 'Stories actives, de la plus ancienne à la plus récente (ordre de lecture).' })
  items!: StoryItemResponse[];
}

export class StoryTrayItemResponse implements StoryTrayItemDto {
  @ApiProperty({ type: UserSummaryResponse })
  user!: UserSummaryResponse;

  @ApiProperty({ type: 'integer', minimum: 1 })
  storiesCount!: number;

  @ApiProperty({ format: 'date-time', description: 'Publication de sa story la plus récente.' })
  latestAt!: string;

  @ApiProperty({ description: 'Au moins une story pas encore vue (toujours faux pour soi).' })
  hasUnseen!: boolean;
}

export class StoryTrayResponse implements StoryTrayDto {
  @ApiProperty({ type: [StoryTrayItemResponse], description: 'Soi d’abord, puis les comptes suivis (100 au plus).' })
  items!: StoryTrayItemResponse[];
}

export class StoryViewerResponse implements StoryViewerDto {
  @ApiProperty({ type: UserSummaryResponse })
  user!: UserSummaryResponse;

  @ApiProperty({ format: 'date-time' })
  viewedAt!: string;

  @ApiProperty()
  liked!: boolean;
}

export class StoryViewersPageResponse implements StoryViewersPageDto {
  @ApiProperty({ type: [StoryViewerResponse] })
  items!: StoryViewerResponse[];

  @ApiProperty({ type: String, nullable: true })
  nextCursor!: string | null;

  @ApiProperty({ type: 'integer', minimum: 0 })
  viewersCount!: number;

  @ApiProperty({ type: 'integer', minimum: 0 })
  likesCount!: number;
}

export class AuthorStoryResponse implements AuthorStoryDto {
  @ApiProperty({ description: 'Au moins une story pas encore vue par le compte connecté (vrai pour un invité).' })
  hasUnseen!: boolean;
}

export class MessageStoryResponse implements MessageStoryDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty({ description: 'Faux si la story a expiré ou a été supprimée.' })
  available!: boolean;

  @ApiPropertyOptional({ enum: ['video', 'photo'], enumName: 'StoryMediaType' })
  mediaType?: StoryMediaType;

  @ApiProperty({ type: String, nullable: true, format: 'uri' })
  thumbnailUrl!: string | null;
}

// Mapping explicite : rawKey et uploadId restent internes à l'API. Partagé par le controller et l'événement WebSocket.
export function toStoryDto(story: Story): StoryDto {
  return {
    id: story.id,
    userId: story.userId,
    mediaType: story.mediaType,
    status: story.status,
    mediaUrl: story.mediaUrl,
    thumbnailUrl: story.thumbnailUrl,
    createdAt: story.createdAt.toISOString(),
    publishedAt: story.publishedAt?.toISOString() ?? null,
    expiresAt: story.expiresAt?.toISOString() ?? null,
  };
}

export function toStoryUploadDto(upload: StoryUpload): StoryUploadDto {
  return {
    story: toStoryDto(upload.story),
    partSize: upload.partSize,
    parts: upload.parts.map((part) => ({ partNumber: part.partNumber, url: part.url })),
    expiresAt: upload.expiresAt.toISOString(),
  };
}

export function toStoryItemDto({ story, viewer, stats }: StoryItem): StoryItemDto {
  return {
    ...toStoryDto(story),
    ...(viewer && { viewer: { viewed: viewer.viewed, liked: viewer.liked } }),
    ...(stats && { stats: { viewersCount: stats.viewersCount, likesCount: stats.likesCount } }),
  };
}

export function toUserStoriesDto({ user, items }: UserStories): UserStoriesDto {
  return { user: toUserSummary(user), items: items.map(toStoryItemDto) };
}

export function toStoryTrayDto(entries: StoryTrayEntry[]): StoryTrayDto {
  return {
    items: entries.map((entry) => ({
      user: toUserSummary(entry.user),
      storiesCount: entry.storiesCount,
      latestAt: entry.latestAt.toISOString(),
      hasUnseen: entry.hasUnseen,
    })),
  };
}

export function toStoryViewersPageDto(page: StoryViewersPage): StoryViewersPageDto {
  return {
    items: page.items.map((entry: StoryViewerEntry) => ({
      user: toUserSummary(entry.user),
      viewedAt: entry.viewedAt.toISOString(),
      liked: entry.liked,
    })),
    nextCursor: page.nextCursor,
    viewersCount: page.viewersCount,
    likesCount: page.likesCount,
  };
}

// Story à laquelle répond un message (module messaging) : disponible tant qu'elle est visible du lecteur.
export function toMessageStoryDto(storyId: string, story: ActiveStory | undefined): MessageStoryDto {
  return story
    ? { id: storyId, available: true, mediaType: story.mediaType, thumbnailUrl: story.thumbnailUrl }
    : { id: storyId, available: false, thumbnailUrl: null };
}
