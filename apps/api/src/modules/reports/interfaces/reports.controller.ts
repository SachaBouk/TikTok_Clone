import { Body, Controller, HttpCode, Post, UseFilters } from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiNoContentResponse,
  ApiNotFoundResponse,
  ApiTags,
  ApiTooManyRequestsResponse,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import { ErrorResponse } from '../../../openapi/error.response';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { ReportsService } from '../application/reports.service';
import { ReportErrorFilter } from './report-error.filter';
import { CreateReportRequest } from './reports.requests';

// Signalements depuis l'app (ADR-038), compte connecté. La file de modération est dans le module admin.
@ApiTags('reports')
@UseFilters(ReportErrorFilter)
@Controller()
export class ReportsController {
  constructor(private readonly reports: ReportsService) {}

  // Idempotent : un second signalement de la même cible, encore ouvert, ne change rien.
  @Post('reports')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Signalement enregistré (ou déjà ouvert).' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Requête invalide, ou son propre contenu.' })
  @ApiUnauthorizedResponse({ type: ErrorResponse, description: 'Access token absent, invalide ou expiré.' })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Contenu introuvable (supprimé, non publié, compte suspendu).' })
  @ApiTooManyRequestsResponse({
    type: ErrorResponse,
    description: 'Trop de signalements envoyés : réessayer après le délai de l’en-tête Retry-After (secondes).',
    // Documenté pour que le client Swift généré l'expose (`headers.retryAfter`).
    headers: { 'Retry-After': { description: 'Secondes à attendre avant de réessayer.', schema: { type: 'integer', minimum: 1 } } },
  })
  async createReport(@CurrentUser() user: AuthenticatedUser, @Body() body: CreateReportRequest): Promise<void> {
    await this.reports.report(user.userId, { target: { type: body.targetType, id: body.targetId }, reason: body.reason, details: body.details });
  }
}
