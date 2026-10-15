import { Body, Controller, Get, HttpCode, Post, Query } from '@nestjs/common';
import { ApiBadRequestResponse, ApiOkResponse, ApiTags, ApiUnauthorizedResponse } from '@nestjs/swagger';
import type { NotificationGroupPageDto, NotificationPageDto, UnreadNotificationsDto } from '@repo/shared';
import { ErrorResponse } from '../../../openapi/error.response';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { NotificationsService } from '../application/notifications.service';
import { MarkNotificationsReadRequest, NotificationGroupsQuery, NotificationListQuery } from './notifications.requests';
import {
  NotificationGroupPageResponse,
  NotificationPageResponse,
  toNotificationDto,
  toNotificationGroupDto,
  UnreadNotificationsResponse,
} from './notifications.responses';

const UNAUTHORIZED = { type: ErrorResponse, description: 'Access token absent, invalide ou expiré.' };

// Centre d'activité du compte connecté (ADR-016) : likes, commentaires, republications et follows reçus.
@ApiTags('notifications')
@Controller('notifications')
export class NotificationsController {
  constructor(private readonly notifications: NotificationsService) {}

  // Une ligne par action. Avec `kind` (et `videoId`) : la liste complète d'un groupe.
  @Get()
  @ApiOkResponse({ type: NotificationPageResponse })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Curseur, taille de page ou filtre invalide.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async listNotifications(@CurrentUser() user: AuthenticatedUser, @Query() query: NotificationListQuery): Promise<NotificationPageDto> {
    const page = await this.notifications.list(user.userId, query.cursor ?? null, query.limit, { type: query.kind, videoId: query.videoId });
    return { items: page.items.map(toNotificationDto), nextCursor: page.nextCursor };
  }

  // Boîte de réception : groupes (« Inès, Nathan et 3 autres ont aimé ta vidéo »). Like et republication par
  // vidéo, tous les follows ensemble, chaque commentaire seul. `kind` répété : seulement ces types (ADR-058).
  @Get('groups')
  @ApiOkResponse({ type: NotificationGroupPageResponse })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Curseur, taille de page ou type invalide.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async listNotificationGroups(@CurrentUser() user: AuthenticatedUser, @Query() query: NotificationGroupsQuery): Promise<NotificationGroupPageDto> {
    const page = await this.notifications.listGroups(user.userId, query.cursor ?? null, query.limit, query.kind);
    return { items: page.items.map(toNotificationGroupDto), nextCursor: page.nextCursor };
  }

  @Get('unread-count')
  @ApiOkResponse({ type: UnreadNotificationsResponse, description: 'Badge du centre d’activité.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async countUnreadNotifications(@CurrentUser() user: AuthenticatedUser): Promise<UnreadNotificationsDto> {
    return { unreadCount: await this.notifications.unreadCount(user.userId) };
  }

  @Post('read')
  @HttpCode(200)
  @ApiOkResponse({ type: UnreadNotificationsResponse, description: 'Badge après le marquage.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Identifiant invalide.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async markNotificationsRead(@CurrentUser() user: AuthenticatedUser, @Body() body: MarkNotificationsReadRequest): Promise<UnreadNotificationsDto> {
    return { unreadCount: await this.notifications.markRead(user.userId, body.upToId ?? null) };
  }
}
