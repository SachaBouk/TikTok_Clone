import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Post, Query, UseFilters } from '@nestjs/common';
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
import type { ConversationDto, ConversationPageDto, MessageDto, MessagePageDto, UnreadConversationsDto } from '@repo/shared';
import { ErrorResponse } from '../../../openapi/error.response';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { MessagingService } from '../application/messaging.service';
import { MessagingErrorFilter } from './messaging-error.filter';
import { MarkConversationReadRequest, OpenConversationRequest, PageQuery, SendMessageRequest } from './messaging.requests';
import {
  ConversationPageResponse,
  ConversationResponse,
  MessagePageResponse,
  MessageResponse,
  toConversationDto,
  toMessageDto,
  toUnreadConversationsDto,
  UnreadConversationsResponse,
} from './messaging.responses';

const ID = new ParseUUIDPipe();
const INVALID_ID = { type: ErrorResponse, description: 'Identifiant invalide.' };
const UNAUTHORIZED = { type: ErrorResponse, description: 'Access token absent, invalide ou expiré.' };
const NOT_FOUND = { type: ErrorResponse, description: 'Conversation inconnue, ou dont le compte n’est pas participant.' };
const PAGE_INVALID = { type: ErrorResponse, description: 'Curseur ou taille de page invalide.' };

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
