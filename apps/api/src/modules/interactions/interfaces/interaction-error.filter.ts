import {
  ArgumentsHost,
  BadRequestException,
  Catch,
  ExceptionFilter,
  ForbiddenException,
  HttpException,
  HttpStatus,
  NotFoundException,
} from '@nestjs/common';
import type { Response } from 'express';
import {
  BlockedError,
  CannotBlockYourselfError,
  CannotFollowYourselfError,
  EmptyCommentError,
  InteractionError,
  InvalidFollowCursorError,
  NotCommentAuthorError,
  TooManyActionsError,
} from '../domain/interaction.errors';

// Traduit les erreurs métier du module en réponses HTTP (ADR-003). 429 porte l'en-tête Retry-After.
@Catch(InteractionError)
export class InteractionErrorFilter implements ExceptionFilter {
  catch(error: InteractionError, host: ArgumentsHost) {
    const response = host.switchToHttp().getResponse<Response>();
    if (error instanceof TooManyActionsError) response.setHeader('Retry-After', String(error.retryAfterSeconds));
    const exception = toHttpException(error);
    response.status(exception.getStatus()).json(exception.getResponse());
  }
}

function toHttpException(error: InteractionError): HttpException {
  if (error instanceof TooManyActionsError) {
    return new HttpException({ statusCode: HttpStatus.TOO_MANY_REQUESTS, message: error.message, error: 'Too Many Requests' }, HttpStatus.TOO_MANY_REQUESTS);
  }
  if (
    error instanceof CannotFollowYourselfError ||
    error instanceof CannotBlockYourselfError ||
    error instanceof EmptyCommentError ||
    error instanceof InvalidFollowCursorError
  ) {
    return new BadRequestException(error.message);
  }
  if (error instanceof NotCommentAuthorError || error instanceof BlockedError) return new ForbiddenException(error.message);
  // VideoNotAvailableError, TargetUserNotFoundError, CommentNotFoundError
  return new NotFoundException(error.message);
}
