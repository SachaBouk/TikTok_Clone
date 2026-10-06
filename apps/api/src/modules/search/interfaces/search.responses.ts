import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import type { AccountSearchItemDto, AccountSearchPageDto, HashtagDto, HashtagListDto } from '@repo/shared';
import { FollowViewerStateResponse } from '../../interactions/interfaces/interactions.responses';
import { toUserSummary, UserSummaryResponse } from '../../users/interfaces/user-summary.response';
import type { Hashtag } from '../../videos/domain/hashtags';
import type { AccountSearchItem } from '../application/search.service';

// Schémas OpenAPI des DTO partagés : `implements` garantit à la compilation que chaque classe suit son type.

export class AccountSearchItemResponse implements AccountSearchItemDto {
  @ApiProperty({ type: UserSummaryResponse })
  user!: UserSummaryResponse;

  @ApiProperty({ type: 'integer', minimum: 0 })
  followersCount!: number;

  // Absent en mode invité (plutôt que null : le client Swift garderait sinon une structure enveloppe).
  @ApiPropertyOptional({ type: FollowViewerStateResponse })
  viewer?: FollowViewerStateResponse;
}

export class AccountSearchPageResponse implements AccountSearchPageDto {
  @ApiProperty({ type: [AccountSearchItemResponse] })
  items!: AccountSearchItemResponse[];

  @ApiProperty({ type: String, nullable: true, description: 'À renvoyer tel quel pour la page suivante ; null s’il n’y en a plus.' })
  nextCursor!: string | null;
}

export class HashtagResponse implements HashtagDto {
  @ApiProperty({ description: 'Nom sans « # », en minuscules.' })
  name!: string;

  @ApiProperty({ type: 'integer', minimum: 0, description: 'Vidéos publiées portant ce hashtag.' })
  videosCount!: number;
}

export class HashtagListResponse implements HashtagListDto {
  @ApiProperty({ type: [HashtagResponse] })
  items!: HashtagResponse[];
}

// Mapping explicite, champ par champ (ADR-003).
export function toAccountSearchItemDto(item: AccountSearchItem): AccountSearchItemDto {
  return {
    user: toUserSummary(item.user),
    followersCount: item.user.followersCount,
    ...(item.viewer ? { viewer: { following: item.viewer.following, followedBy: item.viewer.followedBy } } : {}),
  };
}

export function toHashtagDto(hashtag: Hashtag): HashtagDto {
  return { name: hashtag.name, videosCount: hashtag.videosCount };
}
