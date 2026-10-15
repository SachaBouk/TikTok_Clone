import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post, Put, Query, UseFilters } from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiConflictResponse,
  ApiCreatedResponse,
  ApiForbiddenResponse,
  ApiNoContentResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiTags,
  ApiTooManyRequestsResponse,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import type {
  ConversationDto,
  ConversationPageDto,
  MessageDto,
  MessagePageDto,
  MessageSearchResultListDto,
  UnreadConversationsDto,
} from '@repo/shared';
import { ErrorResponse } from '../../../openapi/error.response';
import { ApiTooManyRequests } from '../../../rate-limit/api-too-many-requests.decorator';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { MessagingService } from '../application/messaging.service';
import { MessagingErrorFilter } from './messaging-error.filter';
import {
  AddGroupMembersRequest,
  CreateGroupRequest,
  MarkConversationReadRequest,
  MessageSearchQuery,
  OpenConversationRequest,
  PageQuery,
  RenameGroupRequest,
  SendMessageRequest,
} from './messaging.requests';
import {
  ConversationPageResponse,
  ConversationResponse,
  MessagePageResponse,
  MessageResponse,
  MessageSearchResultListResponse,
  toConversationDto,
  toMessageSearchResultDto,
  toMessageDto,
  toUnreadConversationsDto,
  UnreadConversationsResponse,
} from './messaging.responses';

const ID = new ParseUUIDPipe();
const INVALID_ID = { type: ErrorResponse, description: 'Identifiant invalide.' };
const UNAUTHORIZED = { type: ErrorResponse, description: 'Access token absent, invalide ou expiré.' };
const NOT_FOUND = { type: ErrorResponse, description: 'Conversation inconnue, ou dont le compte n’est pas participant.' };
const PAGE_INVALID = { type: ErrorResponse, description: 'Curseur ou taille de page invalide.' };
const NOT_A_GROUP = { type: ErrorResponse, description: 'Conversation à deux : action réservée aux groupes.' };

// Messagerie directe du compte connecté (ADR-016). Messages, lectures, demandes et suppressions sont aussi
// poussés par WebSocket (ADR-011) ; un nouveau message, en notification push. Les routes fixes avant `:id`.
@ApiTags('messaging')
@UseFilters(MessagingErrorFilter)
@Controller()
export class MessagingController {
  constructor(private readonly messaging: MessagingService) {}

  @Get('conversations')
  @ApiOkResponse({ type: ConversationPageResponse, description: 'Boîte de réception : conversations acceptées et demandes envoyées.' })
  @ApiBadRequestResponse(PAGE_INVALID)
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async listConversations(@CurrentUser() user: AuthenticatedUser, @Query() query: PageQuery): Promise<ConversationPageDto> {
    const page = await this.messaging.listConversations(user.userId, query.cursor ?? null, query.limit);
    return { items: page.items.map(toConversationDto), nextCursor: page.nextCursor };
  }

  // Recherche dans le texte de ses messages (ADR-058). Déclarée avant `conversations/:id`.
  @Get('conversations/search')
  @ApiOkResponse({ type: MessageSearchResultListResponse, description: 'Messages trouvés, du plus récent au plus ancien.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Texte manquant ou trop long, nombre invalide.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async searchMessages(@CurrentUser() user: AuthenticatedUser, @Query() query: MessageSearchQuery): Promise<MessageSearchResultListDto> {
    const results = await this.messaging.searchMessages(user.userId, query.q, query.limit);
    return { items: results.map(toMessageSearchResultDto) };
  }

  @Get('conversations/requests')
  @ApiOkResponse({ type: ConversationPageResponse, description: 'Demandes reçues en attente (hors comptes bloqués).' })
  @ApiBadRequestResponse(PAGE_INVALID)
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async listMessageRequests(@CurrentUser() user: AuthenticatedUser, @Query() query: PageQuery): Promise<ConversationPageDto> {
    const page = await this.messaging.listRequests(user.userId, query.cursor ?? null, query.limit);
    return { items: page.items.map(toConversationDto), nextCursor: page.nextCursor };
  }

  @Post('conversations')
  @HttpCode(200)
  @ApiOkResponse({ type: ConversationResponse, description: 'La conversation avec ce compte : l’existante, sinon une nouvelle, vide.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Pseudo manquant, ou son propre pseudo.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Pseudo inconnu.' })
  async openConversation(@CurrentUser() user: AuthenticatedUser, @Body() body: OpenConversationRequest): Promise<ConversationDto> {
    return toConversationDto(await this.messaging.openConversation(user.userId, body.username));
  }

  // Chat de groupe (ADR-059). Déclarée avant `conversations/:id`.
  @Post('conversations/groups')
  @ApiCreatedResponse({ type: ConversationResponse, description: 'Le groupe créé ; le créateur en est l’administrateur.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Moins de 2 amis, trop de membres, ou nom trop long.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiForbiddenResponse({ type: ErrorResponse, description: 'Un des comptes n’est pas un ami (abonné mutuel).' })
  @ApiTooManyRequests('Trop de groupes créés')
  async createGroup(@CurrentUser() user: AuthenticatedUser, @Body() body: CreateGroupRequest): Promise<ConversationDto> {
    return toConversationDto(await this.messaging.createGroup(user.userId, { userIds: body.userIds, name: body.name ?? null }));
  }

  @Get('conversations/unread-count')
  @ApiOkResponse({ type: UnreadConversationsResponse, description: 'Badges de la messagerie.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async countUnreadConversations(@CurrentUser() user: AuthenticatedUser): Promise<UnreadConversationsDto> {
    return toUnreadConversationsDto(await this.messaging.badges(user.userId));
  }

  @Get('conversations/:id')
  @ApiOkResponse({ type: ConversationResponse })
  @ApiBadRequestResponse(INVALID_ID)
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(NOT_FOUND)
  async getConversation(@CurrentUser() user: AuthenticatedUser, @Param('id', ID) id: string): Promise<ConversationDto> {
    return toConversationDto(await this.messaging.getConversation(user.userId, id));
  }

  // Pour soi seulement : l'historique disparaît, la conversation réapparaît au prochain message.
  @Delete('conversations/:id')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Conversation supprimée pour le compte connecté ; l’autre participant la garde.' })
  @ApiBadRequestResponse(INVALID_ID)
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(NOT_FOUND)
  async deleteConversation(@CurrentUser() user: AuthenticatedUser, @Param('id', ID) id: string): Promise<void> {
    await this.messaging.deleteConversation(user.userId, id);
  }

  @Post('conversations/:id/accept')
  @HttpCode(200)
  @ApiOkResponse({ type: ConversationResponse, description: 'Demande acceptée : la conversation devient libre pour les deux.' })
  @ApiBadRequestResponse(INVALID_ID)
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(NOT_FOUND)
  @ApiConflictResponse({ type: ErrorResponse, description: 'Pas une demande reçue en attente.' })
  async acceptMessageRequest(@CurrentUser() user: AuthenticatedUser, @Param('id', ID) id: string): Promise<ConversationDto> {
    return toConversationDto(await this.messaging.acceptRequest(user.userId, id));
  }

  @Post('conversations/:id/decline')
  @HttpCode(204)
  @ApiNoContentResponse({
    description: 'Demande refusée : elle disparaît, ses messages suivants ne sont plus remis. L’expéditeur n’est pas prévenu.',
  })
  @ApiBadRequestResponse(INVALID_ID)
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(NOT_FOUND)
  @ApiConflictResponse({ type: ErrorResponse, description: 'Pas une demande reçue en attente.' })
  async declineMessageRequest(@CurrentUser() user: AuthenticatedUser, @Param('id', ID) id: string): Promise<void> {
    await this.messaging.declineRequest(user.userId, id);
  }

  // Renommer un groupe (tout membre) ; un nom vide le retire.
  @Patch('conversations/:id')
  @ApiOkResponse({ type: ConversationResponse })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Nom trop long, ou identifiant invalide.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(NOT_FOUND)
  @ApiConflictResponse(NOT_A_GROUP)
  @ApiTooManyRequests('Trop de messages envoyés')
  async renameGroup(@CurrentUser() user: AuthenticatedUser, @Param('id', ID) id: string, @Body() body: RenameGroupRequest): Promise<ConversationDto> {
    return toConversationDto(await this.messaging.renameGroup(user.userId, id, body.name));
  }

  @Post('conversations/:id/members')
  @HttpCode(200)
  @ApiOkResponse({ type: ConversationResponse, description: 'Le groupe avec ses nouveaux membres (un compte déjà membre est ignoré).' })
  @ApiBadRequestResponse(INVALID_ID)
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiForbiddenResponse({ type: ErrorResponse, description: 'Un des comptes n’est pas un ami (abonné mutuel).' })
  @ApiNotFoundResponse(NOT_FOUND)
  @ApiConflictResponse({ type: ErrorResponse, description: 'Pas un groupe, ou groupe plein (32 membres).' })
  @ApiTooManyRequests('Trop de messages envoyés')
  async addGroupMembers(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ID) id: string,
    @Body() body: AddGroupMembersRequest,
  ): Promise<ConversationDto> {
    return toConversationDto(await this.messaging.addGroupMembers(user.userId, id, body.userIds));
  }

  @Delete('conversations/:id/members/:userId')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Membre retiré par l’administrateur ; il perd la conversation.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Identifiant invalide, ou soi-même (quitter le groupe).' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiForbiddenResponse({ type: ErrorResponse, description: 'Le compte connecté n’est pas l’administrateur du groupe.' })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Groupe inconnu (ou non membre), ou compte qui n’en est pas membre.' })
  @ApiConflictResponse(NOT_A_GROUP)
  async removeGroupMember(@CurrentUser() user: AuthenticatedUser, @Param('id', ID) id: string, @Param('userId', ID) memberId: string): Promise<void> {
    await this.messaging.removeGroupMember(user.userId, id, memberId);
  }

  @Post('conversations/:id/leave')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Groupe quitté ; ses messages restent. Le dernier membre parti, le groupe est supprimé.' })
  @ApiBadRequestResponse(INVALID_ID)
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(NOT_FOUND)
  @ApiConflictResponse(NOT_A_GROUP)
  async leaveGroup(@CurrentUser() user: AuthenticatedUser, @Param('id', ID) id: string): Promise<void> {
    await this.messaging.leaveGroup(user.userId, id);
  }

  @Put('conversations/:id/mute')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Groupe en sourdine : plus de notification push pour le compte connecté.' })
  @ApiBadRequestResponse(INVALID_ID)
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(NOT_FOUND)
  @ApiConflictResponse(NOT_A_GROUP)
  async muteGroup(@CurrentUser() user: AuthenticatedUser, @Param('id', ID) id: string): Promise<void> {
    await this.messaging.setGroupMuted(user.userId, id, true);
  }

  @Delete('conversations/:id/mute')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Sourdine levée.' })
  @ApiBadRequestResponse(INVALID_ID)
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(NOT_FOUND)
  @ApiConflictResponse(NOT_A_GROUP)
  async unmuteGroup(@CurrentUser() user: AuthenticatedUser, @Param('id', ID) id: string): Promise<void> {
    await this.messaging.setGroupMuted(user.userId, id, false);
  }

  @Get('conversations/:id/messages')
  @ApiOkResponse({ type: MessagePageResponse })
  @ApiBadRequestResponse(PAGE_INVALID)
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(NOT_FOUND)
  async listMessages(@CurrentUser() user: AuthenticatedUser, @Param('id', ID) id: string, @Query() query: PageQuery): Promise<MessagePageDto> {
    const page = await this.messaging.listMessages(user.userId, id, query.cursor ?? null, query.limit);
    return { items: page.items.map(toMessageDto), nextCursor: page.nextCursor };
  }

  @Post('conversations/:id/messages')
  @ApiCreatedResponse({ type: MessageResponse })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Ni texte ni vidéo, texte trop long, ou identifiant invalide.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiForbiddenResponse({ type: ErrorResponse, description: 'Blocage entre les deux comptes, ou demande en attente ayant atteint sa limite.' })
  @ApiNotFoundResponse({
    type: ErrorResponse,
    description:
      'Conversation inconnue (ou non participant), vidéo introuvable, story introuvable (expirée, ou pas celle de l’autre participant), ou live introuvable (terminé ou masqué).',
  })
  @ApiConflictResponse({ type: ErrorResponse, description: 'Identifiant d’envoi déjà utilisé pour un message d’une autre conversation.' })
  @ApiTooManyRequestsResponse({
    type: ErrorResponse,
    description: 'Trop de messages envoyés : réessayer après le délai de l’en-tête Retry-After (secondes).',
    // Documenté pour que le client Swift généré l'expose (`headers.retryAfter`).
    headers: { 'Retry-After': { description: 'Secondes à attendre avant de réessayer.', schema: { type: 'integer', minimum: 1 } } },
  })
  async sendMessage(@CurrentUser() user: AuthenticatedUser, @Param('id', ID) id: string, @Body() body: SendMessageRequest): Promise<MessageDto> {
    return toMessageDto(
      await this.messaging.sendMessage(user.userId, id, {
        content: body.content,
        videoId: body.videoId,
        storyId: body.storyId,
        liveId: body.liveId,
        clientMessageId: body.clientMessageId,
      }),
    );
  }

  @Post('conversations/:id/read')
  @HttpCode(200)
  @ApiOkResponse({ type: UnreadConversationsResponse, description: 'Badges de la messagerie après le marquage.' })
  @ApiBadRequestResponse(INVALID_ID)
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(NOT_FOUND)
  async markConversationRead(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ID) id: string,
    @Body() body: MarkConversationReadRequest,
  ): Promise<UnreadConversationsDto> {
    return toUnreadConversationsDto(await this.messaging.markRead(user.userId, id, body.upToId ?? null));
  }

  // Retrait par l'expéditeur, pour les deux participants, sans limite de temps.
  @Delete('messages/:id')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Message retiré pour les deux participants.' })
  @ApiBadRequestResponse(INVALID_ID)
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiForbiddenResponse({ type: ErrorResponse, description: 'Message d’un autre participant.' })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Message inconnu, ou d’une conversation dont le compte n’est pas participant.' })
  async deleteMessage(@CurrentUser() user: AuthenticatedUser, @Param('id', ID) id: string): Promise<void> {
    await this.messaging.deleteMessage(user.userId, id);
  }
}
