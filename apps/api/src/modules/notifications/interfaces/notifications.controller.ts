import { Body, Controller, Get, HttpCode, Post, Query } from '@nestjs/common';
import { ApiBadRequestResponse, ApiOkResponse, ApiTags, ApiUnauthorizedResponse } from '@nestjs/swagger';
import type { NotificationPageDto, UnreadNotificationsDto } from '@repo/shared';
import { ErrorResponse } from '../../../openapi/error.response';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { NotificationsService } from '../application/notifications.service';
import { MarkNotificationsReadRequest, NotificationsQuery } from './notifications.requests';
import { NotificationPageResponse, toNotificationDto, UnreadNotificationsResponse } from './notifications.responses';

const UNAUTHORIZED = { type: ErrorResponse, description: 'Access token absent, invalide ou expiré.' };

// Centre d'activité du compte connecté (ADR-016) : likes, commentaires, republications et follows reçus.
@ApiTags('notifications')
@Controller('notifications')
export class NotificationsController {
  constructor(private readonly notifications: NotificationsService) {}

  @Get()
  @ApiOkResponse({ type: NotificationPageResponse })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Curseur ou taille de page invalide.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async listNotifications(@CurrentUser() user: AuthenticatedUser, @Query() query: NotificationsQuery): Promise<NotificationPageDto> {
    const page = await this.notifications.list(user.userId, query.cursor ?? null, query.limit);
    return { items: page.items.map(toNotificationDto), nextCursor: page.nextCursor };
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
  async markNotificationsRead(
    @CurrentUser() user: AuthenticatedUser,
    @Body() body: MarkNotificationsReadRequest,
  ): Promise<UnreadNotificationsDto> {
    return { unreadCount: await this.notifications.markRead(user.userId, body.upToId ?? null) };
  }
}
