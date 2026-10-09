import {
  ArgumentsHost,
  BadRequestException,
  Catch,
  ConflictException,
  ExceptionFilter,
  ForbiddenException,
  HttpException,
  HttpStatus,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import type { Response } from 'express';
import {
  LiveEndedError,
  LiveError,
  LiveMediaUnavailableError,
  LiveMessageForbiddenError,
  LiveMessageNotFoundError,
  LiveNotFoundError,
  TooManyLiveActionsError,
} from '../domain/live.errors';

// Traduit les erreurs métier du module en réponses HTTP (ADR-003). 429 porte l'en-tête Retry-After.
@Catch(LiveError)
export class LiveErrorFilter implements ExceptionFilter {
  catch(error: LiveError, host: ArgumentsHost) {
    const response = host.switchToHttp().getResponse<Response>();
    if (error instanceof TooManyLiveActionsError) response.setHeader('Retry-After', String(error.retryAfterSeconds));
    const exception = toLiveHttpException(error);
    response.status(exception.getStatus()).json(exception.getResponse());
  }
}

export function toLiveHttpException(error: LiveError): HttpException {
  if (error instanceof TooManyLiveActionsError) {
    return new HttpException(
      { statusCode: HttpStatus.TOO_MANY_REQUESTS, message: error.message, error: 'Too Many Requests' },
      HttpStatus.TOO_MANY_REQUESTS,
    );
  }
  if (error instanceof LiveNotFoundError || error instanceof LiveMessageNotFoundError) return new NotFoundException(error.message);
  if (error instanceof LiveEndedError) return new ConflictException(error.message);
  if (error instanceof LiveMessageForbiddenError) return new ForbiddenException(error.message);
  if (error instanceof LiveMediaUnavailableError) return new ServiceUnavailableException(error.message);
  // InvalidLiveTitleError, InvalidLiveMessageError, InvalidHeartsCountError, OwnLiveError
  return new BadRequestException(error.message);
}
