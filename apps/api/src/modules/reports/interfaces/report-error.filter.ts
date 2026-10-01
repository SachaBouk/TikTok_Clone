import { ArgumentsHost, BadRequestException, Catch, ExceptionFilter, HttpException, HttpStatus, NotFoundException } from '@nestjs/common';
import type { Response } from 'express';
import { CannotReportYourselfError, InvalidReportError, ReportError, TooManyReportsError } from '../domain/report.errors';

// Traduit les erreurs métier du module en réponses HTTP (ADR-003). 429 porte l'en-tête Retry-After.
@Catch(ReportError)
export class ReportErrorFilter implements ExceptionFilter {
  catch(error: ReportError, host: ArgumentsHost) {
    const response = host.switchToHttp().getResponse<Response>();
    if (error instanceof TooManyReportsError) response.setHeader('Retry-After', String(error.retryAfterSeconds));
    const exception = toHttpException(error);
    response.status(exception.getStatus()).json(exception.getResponse());
  }
}

function toHttpException(error: ReportError): HttpException {
  if (error instanceof TooManyReportsError) {
    return new HttpException({ statusCode: HttpStatus.TOO_MANY_REQUESTS, message: error.message, error: 'Too Many Requests' }, HttpStatus.TOO_MANY_REQUESTS);
  }
  if (error instanceof CannotReportYourselfError || error instanceof InvalidReportError) return new BadRequestException(error.message);
  // ReportTargetNotFoundError
  return new NotFoundException(error.message);
}
