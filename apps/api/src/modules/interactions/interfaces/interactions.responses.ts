import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import type {
  AccountSuggestionDto,
  AccountSuggestionListDto,
  BlockedUsersDto,
  CommentDto,
  CommentedVideoDto,
  CommentHistoryItemDto,
  CommentHistoryPageDto,
  CommentPageDto,
  FollowItemDto,
  FollowPageDto,
  FollowViewerStateDto,
  InteractionStateDto,
  ShareResultDto,
  UserRelationshipDto,
  UserRelationshipEntryDto,
  UserRelationshipListDto,
} from '@repo/shared';
import { UserSummaryResponse } from '../../users/interfaces/user-summary.response';

// Schémas OpenAPI des DTO partagés : `implements` garantit à la compilation que chaque classe suit son type.

export class InteractionStateResponse implements InteractionStateDto {
  @ApiProperty({ description: 'Liké / en favori / republié / suivi, après la requête.' })
  active!: boolean;

  @ApiProperty({ type: 'integer', minimum: 0, description: 'Compteur à jour (likes, favoris, republications de la vidéo, ou abonnés du compte).' })
  count!: number;
}

export class ShareResultResponse implements ShareResultDto {
  @ApiProperty({ type: 'integer', minimum: 0 })
  sharesCount!: number;
}

export class CommentResponse implements CommentDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty({ format: 'uuid' })
  videoId!: string;

  @ApiProperty()
  content!: string;

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;

  @ApiProperty({ type: UserSummaryResponse })
  author!: UserSummaryResponse;
}

export class CommentPageResponse implements CommentPageDto {
  @ApiProperty({ type: [CommentResponse], description: 'Du plus récent au plus ancien.' })
  items!: CommentResponse[];

  @ApiProperty({ type: String, nullable: true, format: 'uuid', description: 'À renvoyer tel quel pour la page suivante ; null s’il n’y en a plus.' })
  nextCursor!: string | null;
}

export class BlockedUsersResponse implements BlockedUsersDto {
  @ApiProperty({ type: [UserSummaryResponse], description: 'Du plus récent au plus ancien.' })
  items!: UserSummaryResponse[];
}

export class FollowViewerStateResponse implements FollowViewerStateDto {
  @ApiProperty({ description: 'Le compte connecté suit ce compte.' })
  following!: boolean;

  @ApiProperty({ description: 'Ce compte suit le compte connecté.' })
  followedBy!: boolean;
}

export class FollowItemResponse implements FollowItemDto {
  @ApiProperty({ type: UserSummaryResponse })
  user!: UserSummaryResponse;

  @ApiProperty({ format: 'date-time', description: 'Date du follow.' })
  followedAt!: string;

  // Absent en mode invité. Pas de description : elle produirait un `allOf`, que le client Swift envelopperait.
  @ApiPropertyOptional({ type: FollowViewerStateResponse })
  viewer?: FollowViewerStateResponse;
}

export class FollowPageResponse implements FollowPageDto {
  @ApiProperty({ type: [FollowItemResponse], description: 'Du follow le plus récent au plus ancien.' })
  items!: FollowItemResponse[];

  @ApiProperty({ type: String, nullable: true, description: 'À renvoyer tel quel pour la page suivante ; null s’il n’y en a plus.' })
  nextCursor!: string | null;
}

export class UserRelationshipResponse implements UserRelationshipDto {
  @ApiProperty({ description: 'Le compte connecté suit ce compte.' })
  following!: boolean;

  @ApiProperty({ description: 'Ce compte suit le compte connecté.' })
  followedBy!: boolean;

  @ApiProperty({ description: 'Le compte connecté a bloqué ce compte.' })
  blockedByMe!: boolean;
}

export class UserRelationshipEntryResponse extends UserRelationshipResponse implements UserRelationshipEntryDto {
  @ApiProperty({ format: 'uuid' })
  userId!: string;
}

export class UserRelationshipListResponse implements UserRelationshipListDto {
  @ApiProperty({ type: [UserRelationshipEntryResponse], description: 'Dans l’ordre demandé, sans doublon.' })
  items!: UserRelationshipEntryResponse[];
}

export class CommentedVideoResponse implements CommentedVideoDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty({ format: 'uri' })
  thumbnailUrl!: string;

  @ApiProperty({ type: UserSummaryResponse })
  author!: UserSummaryResponse;
}

export class CommentHistoryItemResponse implements CommentHistoryItemDto {
  @ApiProperty({ format: 'uuid', description: 'Identifiant du commentaire.' })
  id!: string;

  @ApiProperty()
  content!: string;

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;

  @ApiProperty({ type: CommentedVideoResponse })
  video!: CommentedVideoResponse;
}

export class CommentHistoryPageResponse implements CommentHistoryPageDto {
  @ApiProperty({ type: [CommentHistoryItemResponse], description: 'Du plus récent au plus ancien.' })
  items!: CommentHistoryItemResponse[];

  @ApiProperty({ type: String, nullable: true, format: 'uuid', description: 'À renvoyer tel quel pour la page suivante ; null s’il n’y en a plus.' })
  nextCursor!: string | null;
}

export class AccountSuggestionResponse implements AccountSuggestionDto {
  @ApiProperty({ type: UserSummaryResponse })
  user!: UserSummaryResponse;

  @ApiProperty({ type: 'integer', minimum: 0 })
  followersCount!: number;

  @ApiProperty({ description: 'Ce compte suit le compte connecté (« Te suit »).' })
  followsYou!: boolean;

  @ApiProperty({ type: [UserSummaryResponse], description: 'Comptes suivis par le compte connecté qui suivent ce compte, 3 au plus.' })
  followedBy!: UserSummaryResponse[];

  @ApiProperty({ type: 'integer', minimum: 0, description: 'Nombre de comptes suivis par le compte connecté qui suivent ce compte.' })
  followedByCount!: number;
}

export class AccountSuggestionListResponse implements AccountSuggestionListDto {
  @ApiProperty({ type: [AccountSuggestionResponse], description: 'Ceux qui te suivent d’abord, puis par nombre de comptes suivis en commun.' })
  items!: AccountSuggestionResponse[];
}
