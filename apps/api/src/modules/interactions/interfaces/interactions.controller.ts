import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Post, Put, Query, UseFilters } from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiCreatedResponse,
  ApiForbiddenResponse,
  ApiNoContentResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import type {
  BlockedUsersDto,
  CommentDto,
  CommentHistoryPageDto,
  CommentPageDto,
  FollowPageDto,
  InteractionStateDto,
  ShareResultDto,
  UserRelationshipDto,
} from '@repo/shared';
import { ErrorResponse } from '../../../openapi/error.response';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { Public } from '../../auth/interfaces/public.decorator';
import { toUserSummary } from '../../users/interfaces/user-summary.response';
import { InteractionsService, type CommentHistoryPage, type CommentWithAuthor, type FollowPage } from '../application/interactions.service';
import { InteractionErrorFilter } from './interaction-error.filter';
import { CommentsQuery, CreateCommentRequest, FollowsQuery } from './interactions.requests';
import {
  BlockedUsersResponse,
  CommentHistoryPageResponse,
  CommentPageResponse,
  CommentResponse,
  FollowPageResponse,
  InteractionStateResponse,
  ShareResultResponse,
  UserRelationshipResponse,
} from './interactions.responses';

const VIDEO_ID = new ParseUUIDPipe();
const UNAUTHORIZED = { type: ErrorResponse, description: 'Access token absent, invalide ou expiré.' };
const VIDEO_NOT_FOUND = { type: ErrorResponse, description: 'Vidéo inconnue ou pas encore publiée.' };
const BLOCKED = { type: ErrorResponse, description: 'L’un des deux comptes a bloqué l’autre.' };

// Interactions sociales (ADR-016). Liker, commenter, republier et suivre exigent un compte (ADR-010).
// Like, favori, republication et follow sont idempotents : PUT active, DELETE désactive, et la réponse
// porte le compteur à jour.
@ApiTags('interactions')
@UseFilters(InteractionErrorFilter)
@Controller()
export class InteractionsController {
  constructor(private readonly interactions: InteractionsService) {}

  @Put('videos/:id/like')
  @ApiOkResponse({ type: InteractionStateResponse })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(VIDEO_NOT_FOUND)
  @ApiForbiddenResponse(BLOCKED)
  likeVideo(@CurrentUser() user: AuthenticatedUser, @Param('id', VIDEO_ID) id: string): Promise<InteractionStateDto> {
    return this.interactions.setReaction(user.userId, id, 'like', true);
  }

  @Delete('videos/:id/like')
  @ApiOkResponse({ type: InteractionStateResponse })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(VIDEO_NOT_FOUND)
  unlikeVideo(@CurrentUser() user: AuthenticatedUser, @Param('id', VIDEO_ID) id: string): Promise<InteractionStateDto> {
    return this.interactions.setReaction(user.userId, id, 'like', false);
  }

  @Put('videos/:id/favorite')
  @ApiOkResponse({ type: InteractionStateResponse })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(VIDEO_NOT_FOUND)
  favoriteVideo(@CurrentUser() user: AuthenticatedUser, @Param('id', VIDEO_ID) id: string): Promise<InteractionStateDto> {
    return this.interactions.setReaction(user.userId, id, 'favorite', true);
  }

  @Delete('videos/:id/favorite')
  @ApiOkResponse({ type: InteractionStateResponse })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(VIDEO_NOT_FOUND)
  unfavoriteVideo(@CurrentUser() user: AuthenticatedUser, @Param('id', VIDEO_ID) id: string): Promise<InteractionStateDto> {
    return this.interactions.setReaction(user.userId, id, 'favorite', false);
  }

  @Put('videos/:id/repost')
  @ApiOkResponse({ type: InteractionStateResponse })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(VIDEO_NOT_FOUND)
  @ApiForbiddenResponse(BLOCKED)
  repostVideo(@CurrentUser() user: AuthenticatedUser, @Param('id', VIDEO_ID) id: string): Promise<InteractionStateDto> {
    return this.interactions.setReaction(user.userId, id, 'repost', true);
  }

  @Delete('videos/:id/repost')
  @ApiOkResponse({ type: InteractionStateResponse })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(VIDEO_NOT_FOUND)
  unrepostVideo(@CurrentUser() user: AuthenticatedUser, @Param('id', VIDEO_ID) id: string): Promise<InteractionStateDto> {
    return this.interactions.setReaction(user.userId, id, 'repost', false);
  }

  // Historique de visionnage (ADR-006, ADR-016) : réservé aux comptes connectés ; en mode invité, l'app n'appelle pas.
  @Post('videos/:id/view')
  @HttpCode(204)
  @ApiNoContentResponse({
    description: 'Visionnage enregistré (à envoyer après ~1 s de lecture). Sans effet sur ses propres vidéos.',
  })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(VIDEO_NOT_FOUND)
  async recordView(@CurrentUser() user: AuthenticatedUser, @Param('id', VIDEO_ID) id: string): Promise<void> {
    await this.interactions.recordView(user.userId, id);
  }

  // La grille de l'historique est servie par le module feed (`GET /users/me/history`).
  @Delete('users/me/history/:videoId')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Vidéo retirée de l’historique (sans effet si elle n’y était pas).' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async removeFromHistory(@CurrentUser() user: AuthenticatedUser, @Param('videoId', VIDEO_ID) videoId: string): Promise<void> {
    await this.interactions.removeFromHistory(user.userId, videoId);
  }

  @Delete('users/me/history')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Historique effacé.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async clearHistory(@CurrentUser() user: AuthenticatedUser): Promise<void> {
    await this.interactions.clearHistory(user.userId);
  }

  // Public : partager un lien ne demande pas de compte (ADR-010 ne l'exige que pour liker, commenter, publier, suivre).
  @Public()
  @Post('videos/:id/share')
  @HttpCode(200)
  @ApiOkResponse({ type: ShareResultResponse, description: 'À appeler quand l’utilisateur partage le lien de la vidéo.' })
  @ApiNotFoundResponse(VIDEO_NOT_FOUND)
  async shareVideo(@Param('id', VIDEO_ID) id: string): Promise<ShareResultDto> {
    return { sharesCount: await this.interactions.share(id) };
  }

  // Public. Connecté : les commentaires des comptes bloqués (dans un sens ou dans l'autre) sont retirés.
  @Public()
  @Get('videos/:id/comments')
  @ApiOkResponse({ type: CommentPageResponse })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Curseur ou taille de page invalide.' })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Vidéo inconnue, pas encore publiée, ou d’un compte bloqué.' })
  async listComments(
    @CurrentUser() user: AuthenticatedUser | undefined,
    @Param('id', VIDEO_ID) id: string,
    @Query() query: CommentsQuery,
  ): Promise<CommentPageDto> {
    const page = await this.interactions.listComments(id, query.cursor ?? null, query.limit, user?.userId ?? null);
    return { items: page.items.map(toCommentDto), nextCursor: page.nextCursor };
  }

  @Post('videos/:id/comments')
  @ApiCreatedResponse({ type: CommentResponse })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Commentaire vide ou trop long.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(VIDEO_NOT_FOUND)
  @ApiForbiddenResponse(BLOCKED)
  async addComment(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', VIDEO_ID) id: string,
    @Body() body: CreateCommentRequest,
  ): Promise<CommentDto> {
    return toCommentDto(await this.interactions.addComment(user.userId, id, body.content));
  }

  // Centre d'activités : ses propres commentaires, privés. Suppression : `DELETE /comments/:id`.
  @Get('users/me/comments')
  @ApiOkResponse({ type: CommentHistoryPageResponse })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Curseur ou taille de page invalide.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async listMyComments(@CurrentUser() user: AuthenticatedUser, @Query() query: CommentsQuery): Promise<CommentHistoryPageDto> {
    return toCommentHistoryDto(await this.interactions.listCommentHistory(user.userId, query.cursor ?? null, query.limit));
  }

  @Delete('comments/:id')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Commentaire supprimé.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiForbiddenResponse({ type: ErrorResponse, description: 'Commentaire d’un autre utilisateur.' })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Commentaire inconnu.' })
  async deleteComment(@CurrentUser() user: AuthenticatedUser, @Param('id', new ParseUUIDPipe()) id: string): Promise<void> {
    await this.interactions.deleteComment(user.userId, id);
  }

  @Put('users/:username/follow')
  @ApiOkResponse({ type: InteractionStateResponse, description: '`count` : abonnés du compte suivi.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Impossible de se suivre soi-même.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Pseudo inconnu.' })
  @ApiForbiddenResponse(BLOCKED)
  followUser(@CurrentUser() user: AuthenticatedUser, @Param('username') username: string): Promise<InteractionStateDto> {
    return this.interactions.setFollow(user.userId, username, true);
  }

  @Delete('users/:username/follow')
  @ApiOkResponse({ type: InteractionStateResponse, description: '`count` : abonnés du compte.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Impossible de se suivre soi-même.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Pseudo inconnu.' })
  unfollowUser(@CurrentUser() user: AuthenticatedUser, @Param('username') username: string): Promise<InteractionStateDto> {
    return this.interactions.setFollow(user.userId, username, false);
  }

  // Écran de profil d'un autre compte : état des boutons « Suivre » et « Débloquer ». Le profil lui-même
  // est servi par `GET /users/:username` (module users, qui ne dépend pas des interactions).
  @Get('users/:username/relationship')
  @ApiOkResponse({ type: UserRelationshipResponse })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Pseudo inconnu.' })
  async getRelationship(@CurrentUser() user: AuthenticatedUser, @Param('username') username: string): Promise<UserRelationshipDto> {
    const relationship = await this.interactions.getRelationship(user.userId, username);
    return { following: relationship.following, followedBy: relationship.followedBy, blockedByMe: relationship.blockedByMe };
  }

  // Listes publiques (mode invité compris) ; `viewer` n'est renseigné que pour un compte connecté.
  // Connecté : les comptes bloqués (dans un sens ou dans l'autre) sont retirés, et leurs listes sont vides.
  @Public()
  @Get('users/:username/followers')
  @ApiOkResponse({ type: FollowPageResponse, description: 'Abonnés du compte.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Curseur ou taille de page invalide.' })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Pseudo inconnu.' })
  async listFollowers(
    @CurrentUser() user: AuthenticatedUser | undefined,
    @Param('username') username: string,
    @Query() query: FollowsQuery,
  ): Promise<FollowPageDto> {
    return toFollowPageDto(await this.interactions.listFollows('followers', username, user?.userId, query.cursor ?? null, query.limit));
  }

  @Public()
  @Get('users/:username/following')
  @ApiOkResponse({ type: FollowPageResponse, description: 'Comptes suivis par le compte.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Curseur ou taille de page invalide.' })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Pseudo inconnu.' })
  async listFollowing(
    @CurrentUser() user: AuthenticatedUser | undefined,
    @Param('username') username: string,
    @Query() query: FollowsQuery,
  ): Promise<FollowPageDto> {
    return toFollowPageDto(await this.interactions.listFollows('following', username, user?.userId, query.cursor ?? null, query.limit));
  }

  // Blocage (ADR-016) : dans les deux sens, ni messages, ni follows, ni likes, commentaires ou republications.
  // Bloquer supprime les follows mutuels et les notifications échangées. Idempotent.
  @Put('users/:username/block')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Compte bloqué.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Impossible de se bloquer soi-même.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Pseudo inconnu.' })
  async blockUser(@CurrentUser() user: AuthenticatedUser, @Param('username') username: string): Promise<void> {
    await this.interactions.setBlock(user.userId, username, true);
  }

  @Delete('users/:username/block')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Compte débloqué (les follows ne sont pas rétablis).' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Impossible de se bloquer soi-même.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Pseudo inconnu.' })
  async unblockUser(@CurrentUser() user: AuthenticatedUser, @Param('username') username: string): Promise<void> {
    await this.interactions.setBlock(user.userId, username, false);
  }

  @Get('users/me/blocks')
  @ApiOkResponse({ type: BlockedUsersResponse })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async listBlockedUsers(@CurrentUser() user: AuthenticatedUser): Promise<BlockedUsersDto> {
    return { items: (await this.interactions.listBlockedUsers(user.userId)).map(toUserSummary) };
  }
}

// Mapping explicite : rien n'est exposé par accident (ADR-003).
function toCommentDto({ comment, author }: CommentWithAuthor): CommentDto {
  return {
    id: comment.id,
    videoId: comment.videoId,
    content: comment.content,
    createdAt: comment.createdAt.toISOString(),
    author: toUserSummary(author),
  };
}

function toFollowPageDto(page: FollowPage): FollowPageDto {
  return {
    items: page.items.map((item) => ({
      user: toUserSummary(item.user),
      followedAt: item.followedAt.toISOString(),
      ...(item.viewer ? { viewer: { following: item.viewer.following, followedBy: item.viewer.followedBy } } : {}),
    })),
    nextCursor: page.nextCursor,
  };
}

function toCommentHistoryDto(page: CommentHistoryPage): CommentHistoryPageDto {
  return {
    items: page.items.map(({ comment, video, videoAuthor }) => ({
      id: comment.id,
      content: comment.content,
      createdAt: comment.createdAt.toISOString(),
      video: { id: video.id, thumbnailUrl: video.thumbnailUrl, author: toUserSummary(videoAuthor) },
    })),
    nextCursor: page.nextCursor,
  };
}
