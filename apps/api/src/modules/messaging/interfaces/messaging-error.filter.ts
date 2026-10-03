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
} from '@nestjs/common';
import type { Response } from 'express';
import {
  BlockedConversationError,
  CannotMessageYourselfError,
  ClientMessageIdConflictError,
  EmptyMessageError,
  MessagingError,
  NotAPendingRequestError,
  NotMessageSenderError,
  RateLimitedError,
  RequestLimitReachedError,
} from '../domain/messaging.errors';

// Traduit les erreurs métier du module en réponses HTTP (ADR-003). 429 porte l'en-tête Retry-After.
@Catch(MessagingError)
export class MessagingErrorFilter implements ExceptionFilter {
  catch(error: MessagingError, host: ArgumentsHost) {
    const response = host.switchToHttp().getResponse<Response>();
    if (error instanceof RateLimitedError) response.setHeader('Retry-After', String(error.retryAfterSeconds));
    const exception = toHttpException(error);
    response.status(exception.getStatus()).json(exception.getResponse());
  }
}

function toHttpException(error: MessagingError): HttpException {
  if (error instanceof CannotMessageYourselfError || error instanceof EmptyMessageError) return new BadRequestException(error.message);
  if (error instanceof BlockedConversationError || error instanceof RequestLimitReachedError || error instanceof NotMessageSenderError) {
    return new ForbiddenException(error.message);
  }
  if (error instanceof NotAPendingRequestError || error instanceof ClientMessageIdConflictError) return new ConflictException(error.message);
  if (error instanceof RateLimitedError) {
    return new HttpException(
      { statusCode: HttpStatus.TOO_MANY_REQUESTS, message: error.message, error: 'Too Many Requests' },
      HttpStatus.TOO_MANY_REQUESTS,
    );
  }
  // ConversationNotFoundError, MessageNotFoundError, RecipientNotFoundError, SharedVideoNotFoundError
  return new NotFoundException(error.message);
}
