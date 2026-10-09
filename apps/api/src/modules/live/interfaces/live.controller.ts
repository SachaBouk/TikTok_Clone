import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Post, UseFilters } from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiConflictResponse,
  ApiCreatedResponse,
  ApiForbiddenResponse,
  ApiNoContentResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiPropertyOptional,
  ApiServiceUnavailableResponse,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import type { FollowingLivesDto, LiveChatMessageDto, LiveConnectionDto, LiveHeartsDto, LiveItemDto } from '@repo/shared';
import { ErrorResponse } from '../../../openapi/error.response';
import { ApiTooManyRequests } from '../../../rate-limit/api-too-many-requests.decorator';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { Public } from '../../auth/interfaces/public.decorator';
import { UsersService } from '../../users/application/users.service';
import { UserErrorFilter } from '../../users/interfaces/user-error.filter';
import { LiveService } from '../application/live.service';
import { LiveErrorFilter } from './live-error.filter';
import { SendLiveHeartsRequest, SendLiveMessageRequest, StartLiveRequest } from './live.requests';
import {
  FollowingLivesResponse,
  LiveChatMessageResponse,
  LiveConnectionResponse,
  LiveHeartsResponse,
  LiveResponse,
  toLiveChatMessageDto,
  toLiveConnectionDto,
  toLiveItemDto,
} from './live.responses';

const UNAUTHORIZED = { type: ErrorResponse, description: 'Access token absent, invalide ou expiré.' };
const NOT_FOUND = { type: ErrorResponse, description: 'Live inconnu, ou masqué (blocage, auteur suspendu).' };
const ENDED = { type: ErrorResponse, description: 'Live terminé.' };

// Live en cours d'un compte (anneau « EN DIRECT » du profil).
class UserLiveResponse {
  // Absent : aucun live en cours visible.
  @ApiPropertyOptional({ type: LiveResponse })
  live?: LiveResponse;
}

// Live (ADR-053) : la vidéo passe par le serveur LiveKit ; ces routes ouvrent et ferment la salle, délivrent les jetons
// d'accès, et portent le chat et les cœurs (diffusés dans la salle). Regarder est public ; le reste demande un compte.
@ApiTags('live')
@UseFilters(LiveErrorFilter)
@Controller('lives')
export class LiveController {
  constructor(private readonly lives: LiveService) {}

  @Post()
  @ApiCreatedResponse({
    type: LiveConnectionResponse,
    description: 'Live lancé (ou repris s’il est déjà en cours), abonnés prévenus. Se connecter à `url` avec `token` et publier caméra et micro.',
  })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Titre trop long.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiServiceUnavailableResponse({ type: ErrorResponse, description: 'Serveur vidéo indisponible : rien n’est lancé.' })
  @ApiTooManyRequests('Trop de lives lancés récemment (10 par jour)')
  async startLive(@CurrentUser() user: AuthenticatedUser, @Body() body: StartLiveRequest): Promise<LiveConnectionDto> {
    return toLiveConnectionDto(await this.lives.start(user.userId, { title: body.title ?? null }));
  }

  @Get('following')
  @ApiOkResponse({ type: FollowingLivesResponse })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async listFollowingLives(@CurrentUser() user: AuthenticatedUser): Promise<FollowingLivesDto> {
    return { items: (await this.lives.listFollowingLives(user.userId)).map(toLiveItemDto) };
  }

  // Public : un live en cours ou terminé (écran « Live terminé ») ; ses chiffres pour son auteur.
  @Public()
  @Get(':id')
  @ApiOkResponse({ type: LiveResponse })
  @ApiNotFoundResponse(NOT_FOUND)
  async getLive(@CurrentUser() user: AuthenticatedUser | undefined, @Param('id', new ParseUUIDPipe()) id: string): Promise<LiveItemDto> {
    return toLiveItemDto(await this.lives.getLive(id, user?.userId ?? null));
  }

  // Public : un invité regarde aussi (lecture seule). L'auteur qui revient reçoit un jeton pour publier.
  @Public()
  @Post(':id/join')
  @HttpCode(200)
  @ApiOkResponse({ type: LiveConnectionResponse, description: 'Jeton d’accès à la salle et derniers messages du chat.' })
  @ApiNotFoundResponse(NOT_FOUND)
  @ApiConflictResponse(ENDED)
  async joinLive(@CurrentUser() user: AuthenticatedUser | undefined, @Param('id', new ParseUUIDPipe()) id: string): Promise<LiveConnectionDto> {
    return toLiveConnectionDto(await this.lives.join(id, user?.userId ?? null));
  }

  // Par son auteur. Idempotent : un live déjà terminé est rendu tel quel.
  @Post(':id/end')
  @HttpCode(200)
  @ApiOkResponse({ type: LiveResponse, description: 'Live terminé, avec ses chiffres.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Live inconnu ou d’un autre compte.' })
  async endLive(@CurrentUser() user: AuthenticatedUser, @Param('id', new ParseUUIDPipe()) id: string): Promise<LiveItemDto> {
    return toLiveItemDto(await this.lives.stop(user.userId, id));
  }

  @Post(':id/messages')
  @ApiCreatedResponse({ type: LiveChatMessageResponse, description: 'Message envoyé, diffusé dans la salle.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Message vide ou trop long (150 caractères).' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(NOT_FOUND)
  @ApiConflictResponse(ENDED)
  @ApiTooManyRequests('Trop de messages envoyés récemment')
  async sendLiveMessage(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) id: string,
    @Body() body: SendLiveMessageRequest,
  ): Promise<LiveChatMessageDto> {
    const { message, author } = await this.lives.sendMessage(user.userId, id, body.content);
    return toLiveChatMessageDto(message, author);
  }

  // Par l'auteur du message ou celui du live ; retiré pour toute la salle.
  @Delete(':id/messages/:messageId')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Message retiré.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiForbiddenResponse({ type: ErrorResponse, description: 'Ni l’auteur du message, ni celui du live.' })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Live ou message inconnu.' })
  async deleteLiveMessage(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) id: string,
    @Param('messageId', new ParseUUIDPipe()) messageId: string,
  ): Promise<void> {
    await this.lives.deleteMessage(user.userId, id, messageId);
  }

  @Post(':id/hearts')
  @HttpCode(200)
  @ApiOkResponse({ type: LiveHeartsResponse })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Nombre de cœurs invalide, ou son propre live.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(NOT_FOUND)
  @ApiConflictResponse(ENDED)
  @ApiTooManyRequests('Trop de cœurs envoyés récemment')
  async sendLiveHearts(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) id: string,
    @Body() body: SendLiveHeartsRequest,
  ): Promise<LiveHeartsDto> {
    return { total: await this.lives.sendHearts(user.userId, id, body.count) };
  }
}

// Live en cours d'un compte, pour son profil (public).
@ApiTags('live')
@UseFilters(LiveErrorFilter, UserErrorFilter)
@Controller('users')
export class UserLiveController {
  constructor(
    private readonly lives: LiveService,
    private readonly users: UsersService,
  ) {}

  @Public()
  @Get(':username/live')
  @ApiOkResponse({ type: UserLiveResponse, description: '`live` absent si le compte n’a pas de live en cours visible.' })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Compte inconnu.' })
  async getUserLive(@CurrentUser() user: AuthenticatedUser | undefined, @Param('username') username: string): Promise<{ live?: LiveItemDto }> {
    const account = await this.users.getByUsername(username);
    const live = (await this.lives.getLiveRings([account.id], user?.userId ?? null)).get(account.id);
    return live ? { live: toLiveItemDto({ live, host: account }) } : {};
  }
}
