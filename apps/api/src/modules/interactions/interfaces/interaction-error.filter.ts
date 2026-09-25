import {
  ArgumentsHost,
  BadRequestException,
  Catch,
  ExceptionFilter,
  ForbiddenException,
  HttpException,
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
} from '../domain/interaction.errors';

// Traduit les erreurs métier du module en réponses HTTP (ADR-003).
@Catch(InteractionError)
export class InteractionErrorFilter implements ExceptionFilter {
  catch(error: InteractionError, host: ArgumentsHost) {
    const exception = toHttpException(error);
    host.switchToHttp().getResponse<Response>().status(exception.getStatus()).json(exception.getResponse());
  }
}

function toHttpException(error: InteractionError): HttpException {
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
