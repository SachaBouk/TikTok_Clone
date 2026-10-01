import { Body, Controller, Delete, Get, HttpCode, Param, ParseEnumPipe, ParseUUIDPipe, Post, Put, Query, UseFilters } from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiConflictResponse,
  ApiNoContentResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiParam,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import type {
  AdminCommentPageDto,
  AdminModerationActionPageDto,
  AdminReportTargetDetailDto,
  AdminReportTargetPageDto,
  AdminStatsDto,
  AdminUserDto,
  AdminUserPageDto,
  AdminVideoDto,
  AdminVideoPageDto,
  AdminWalletTransactionPageDto,
  ReportTargetType,
} from '@repo/shared';
import { ErrorResponse } from '../../../openapi/error.response';
import { AdminOnly } from '../../auth/interfaces/admin-only.decorator';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { AdminService } from '../application/admin.service';
import { AdminErrorFilter } from './admin-error.filter';
import {
  AdminCommentsQuery,
  AdminModerationActionsQuery,
  AdminRemovalQuery,
  AdminReportsQuery,
  AdminSuspendRequest,
  AdminUsersQuery,
  AdminVideosQuery,
  AdminWalletTransactionsQuery,
} from './admin.requests';
import { REPORT_TARGET_TYPES } from '../../reports/domain/report';
import {
  AdminCommentPageResponse,
  AdminModerationActionPageResponse,
  AdminReportTargetDetailResponse,
  AdminReportTargetPageResponse,
  AdminStatsResponse,
  AdminUserPageResponse,
  AdminUserResponse,
  AdminVideoPageResponse,
  AdminVideoResponse,
  AdminWalletTransactionPageResponse,
  toAdminCommentDto,
  toAdminModerationActionDto,
  toAdminReportTargetDetailDto,
  toAdminReportTargetDto,
  toAdminStatsDto,
  toAdminUserDto,
  toAdminVideoDto,
  toAdminWalletTransactionDto,
} from './admin.responses';

const INVALID_QUERY = { type: ErrorResponse, description: 'Paramètre invalide (curseur, limite, filtre).' };
const TARGET_TYPE = new ParseEnumPipe({ video: 'video', comment: 'comment', account: 'account', message: 'message' });
const TARGET_TYPE_PARAM = { name: 'targetType', enum: REPORT_TARGET_TYPES, enumName: 'ReportTargetType' };
const REMOVAL_REFUSED = { type: ErrorResponse, description: 'Identifiant ou motif invalide.' };

// Routes du backoffice (ADR-004), toutes réservées aux administrateurs (@AdminOnly : 403 sinon).
// Couche `interfaces/` : traduit HTTP ↔ service applicatif, sans logique métier (ADR-003).
@ApiTags('admin')
@AdminOnly()
@ApiUnauthorizedResponse({ type: ErrorResponse, description: 'Access token absent, invalide ou expiré.' })
@UseFilters(AdminErrorFilter)
@Controller('admin')
export class AdminController {
  constructor(private readonly adminService: AdminService) {}

  // Compte connecté : le backoffice l'appelle à la connexion pour vérifier le rôle.
  @Get('me')
  @ApiOkResponse({ type: AdminUserResponse })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Compte supprimé.' })
  async getAdminSession(@CurrentUser() user: AuthenticatedUser): Promise<AdminUserDto> {
    return toAdminUserDto(await this.adminService.getAccount(user.userId));
  }

  @Get('stats')
  @ApiOkResponse({ type: AdminStatsResponse })
  async getAdminStats(): Promise<AdminStatsDto> {
    return toAdminStatsDto(await this.adminService.getStats());
  }

  @Get('users')
  @ApiOkResponse({ type: AdminUserPageResponse })
  @ApiBadRequestResponse(INVALID_QUERY)
  async listAdminUsers(@Query() query: AdminUsersQuery): Promise<AdminUserPageDto> {
    const page = await this.adminService.listAccounts(query.q ?? null, query.cursor ?? null, query.limit);
    return { items: page.items.map(toAdminUserDto), nextCursor: page.nextCursor };
  }

  @Get('users/:id')
  @ApiOkResponse({ type: AdminUserResponse })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Identifiant invalide.' })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Compte introuvable.' })
  async getAdminUser(@Param('id', ParseUUIDPipe) id: string): Promise<AdminUserDto> {
    return toAdminUserDto(await this.adminService.getAccount(id));
  }

  // Suspension (ADR-037) : connexion refusée, sessions et WebSocket fermés, contenus masqués jusqu'à la levée.
  @Put('users/:id/suspension')
  @ApiOkResponse({ type: AdminUserResponse, description: 'Le compte, suspendu (suspension inchangée s’il l’était déjà).' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Identifiant ou motif invalide.' })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Compte introuvable.' })
  @ApiConflictResponse({ type: ErrorResponse, description: 'Compte administrateur (retirer d’abord son rôle), ou son propre compte.' })
  async suspendAdminUser(
    @CurrentUser() admin: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() body: AdminSuspendRequest,
  ): Promise<AdminUserDto> {
    return toAdminUserDto(await this.adminService.suspendAccount(admin.userId, id, body.reason));
  }

  @Delete('users/:id/suspension')
  @ApiOkResponse({ type: AdminUserResponse, description: 'Le compte, suspension levée (idempotent).' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Identifiant invalide.' })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Compte introuvable.' })
  async liftAdminUserSuspension(@CurrentUser() admin: AuthenticatedUser, @Param('id', ParseUUIDPipe) id: string): Promise<AdminUserDto> {
    return toAdminUserDto(await this.adminService.liftSuspension(admin.userId, id));
  }

  @Get('videos')
  @ApiOkResponse({ type: AdminVideoPageResponse })
  @ApiBadRequestResponse(INVALID_QUERY)
  async listAdminVideos(@Query() query: AdminVideosQuery): Promise<AdminVideoPageDto> {
    const page = await this.adminService.listVideos({ status: query.status, userId: query.userId }, query.cursor ?? null, query.limit);
    return { items: page.items.map(toAdminVideoDto), nextCursor: page.nextCursor };
  }

  @Get('videos/:id')
  @ApiOkResponse({ type: AdminVideoResponse })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Identifiant invalide.' })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Vidéo introuvable.' })
  async getAdminVideo(@Param('id', ParseUUIDPipe) id: string): Promise<AdminVideoDto> {
    return toAdminVideoDto(await this.adminService.getVideo(id));
  }

  // Retrait par modération, quel que soit le statut : suppression réelle, fichiers nettoyés ensuite.
  @Delete('videos/:id')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Vidéo supprimée, avec ses likes, commentaires et notifications ; auteur prévenu avec le motif.' })
  @ApiBadRequestResponse(REMOVAL_REFUSED)
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Vidéo introuvable ou déjà supprimée.' })
  async deleteAdminVideo(
    @CurrentUser() admin: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Query() query: AdminRemovalQuery,
  ): Promise<void> {
    await this.adminService.removeVideo(admin.userId, id, query.reason);
  }

  // Retrait d'un message signalé (ADR-038), pour les deux participants ; l'expéditeur est prévenu avec le motif.
  @Delete('messages/:id')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Message retiré pour les deux participants ; expéditeur prévenu avec le motif.' })
  @ApiBadRequestResponse(REMOVAL_REFUSED)
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Message introuvable ou déjà retiré.' })
  async deleteAdminMessage(
    @CurrentUser() admin: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Query() query: AdminRemovalQuery,
  ): Promise<void> {
    await this.adminService.removeMessage(admin.userId, id, query.reason);
  }

  // Journal de modération (ADR-038) : toutes les actions des administrateurs, ou celles sur un compte.
  @Get('moderation-actions')
  @ApiOkResponse({ type: AdminModerationActionPageResponse })
  @ApiBadRequestResponse(INVALID_QUERY)
  async listAdminModerationActions(@Query() query: AdminModerationActionsQuery): Promise<AdminModerationActionPageDto> {
    const page = await this.adminService.listModerationActions({ targetUserId: query.userId }, query.cursor ?? null, query.limit);
    const users = await this.adminService.usersByIds(page.items.flatMap((a) => [a.adminId, a.targetUserId].filter((id): id is string => !!id)));
    return { items: page.items.map((action) => toAdminModerationActionDto(action, users)), nextCursor: page.nextCursor };
  }

  @Get('comments')
  @ApiOkResponse({ type: AdminCommentPageResponse })
  @ApiBadRequestResponse(INVALID_QUERY)
  async listAdminComments(@Query() query: AdminCommentsQuery): Promise<AdminCommentPageDto> {
    const page = await this.adminService.listComments({ videoId: query.videoId, userId: query.userId }, query.cursor ?? null, query.limit);
    return { items: page.items.map(toAdminCommentDto), nextCursor: page.nextCursor };
  }

  // Journal des jetons (ADR-009, ADR-021) : tous les comptes, lignes anonymisées et clients inconnus compris.
  @Get('wallet-transactions')
  @ApiOkResponse({ type: AdminWalletTransactionPageResponse })
  @ApiBadRequestResponse(INVALID_QUERY)
  async listAdminWalletTransactions(@Query() query: AdminWalletTransactionsQuery): Promise<AdminWalletTransactionPageDto> {
    const page = await this.adminService.listWalletTransactions({ userId: query.userId, unmatched: query.unmatched }, query.cursor ?? null, query.limit);
    return { items: page.items.map(toAdminWalletTransactionDto), nextCursor: page.nextCursor };
  }

  @Delete('comments/:id')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Commentaire supprimé, avec sa notification ; auteur prévenu avec le motif.' })
  @ApiBadRequestResponse(REMOVAL_REFUSED)
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Commentaire introuvable ou déjà supprimé.' })
  async deleteAdminComment(
    @CurrentUser() admin: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Query() query: AdminRemovalQuery,
  ): Promise<void> {
    await this.adminService.removeComment(admin.userId, id, query.reason);
  }

  // File des signalements (ADR-038), groupés par cible. Supprimer le contenu (routes ci-dessus) ou suspendre le compte
  // clôt les signalements ouverts ; sinon, classement sans suite.
  @Get('reports')
  @ApiOkResponse({ type: AdminReportTargetPageResponse })
  @ApiBadRequestResponse(INVALID_QUERY)
  async listAdminReports(@Query() query: AdminReportsQuery): Promise<AdminReportTargetPageDto> {
    const page = await this.adminService.listReportTargets(query.cursor ?? null, query.limit);
    return { items: page.items.map(toAdminReportTargetDto), nextCursor: page.nextCursor };
  }

  @Get('reports/:targetType/:targetId')
  @ApiParam(TARGET_TYPE_PARAM)
  @ApiOkResponse({ type: AdminReportTargetDetailResponse })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Type ou identifiant invalide.' })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Aucun signalement pour cette cible.' })
  async getAdminReportTarget(
    @Param('targetType', TARGET_TYPE) targetType: ReportTargetType,
    @Param('targetId', ParseUUIDPipe) targetId: string,
  ): Promise<AdminReportTargetDetailDto> {
    return toAdminReportTargetDetailDto(await this.adminService.getReportTarget({ type: targetType, id: targetId }));
  }

  @Post('reports/:targetType/:targetId/dismiss')
  @HttpCode(204)
  @ApiParam(TARGET_TYPE_PARAM)
  @ApiNoContentResponse({ description: 'Signalements ouverts classés sans suite ; le contenu reste en ligne.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Type ou identifiant invalide.' })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Aucun signalement ouvert pour cette cible.' })
  async dismissAdminReports(
    @CurrentUser() admin: AuthenticatedUser,
    @Param('targetType', TARGET_TYPE) targetType: ReportTargetType,
    @Param('targetId', ParseUUIDPipe) targetId: string,
  ): Promise<void> {
    await this.adminService.dismissReports(admin.userId, { type: targetType, id: targetId });
  }
}
