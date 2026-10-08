import {
  ArgumentsHost,
  BadRequestException,
  Catch,
  ConflictException,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  NotFoundException,
} from '@nestjs/common';
import type { Response } from 'express';
import {
  StoryAuthorNotFoundError,
  StoryError,
  StoryNotAwaitingUploadError,
  StoryNotFoundError,
  TooManyActiveStoriesError,
  TooManyStoryActionsError,
} from '../domain/story.errors';

// Traduit les erreurs métier du module en réponses HTTP (ADR-003). 429 porte l'en-tête Retry-After.
@Catch(StoryError)
export class StoryErrorFilter implements ExceptionFilter {
  catch(error: StoryError, host: ArgumentsHost) {
    const response = host.switchToHttp().getResponse<Response>();
    if (error instanceof TooManyStoryActionsError) response.setHeader('Retry-After', String(error.retryAfterSeconds));
    const exception = toHttpException(error);
    response.status(exception.getStatus()).json(exception.getResponse());
  }
}

function toHttpException(error: StoryError): HttpException {
  if (error instanceof TooManyStoryActionsError) {
    return new HttpException(
      { statusCode: HttpStatus.TOO_MANY_REQUESTS, message: error.message, error: 'Too Many Requests' },
      HttpStatus.TOO_MANY_REQUESTS,
    );
  }
  if (error instanceof StoryNotFoundError || error instanceof StoryAuthorNotFoundError) return new NotFoundException(error.message);
  if (error instanceof StoryNotAwaitingUploadError || error instanceof TooManyActiveStoriesError) return new ConflictException(error.message);
  // UnsupportedStoryTypeError, StoryTooLargeError, StoryUploadIncompleteError, InvalidStoryPhotoError, OwnStoryError,
  // InvalidStoryCursorError
  return new BadRequestException(error.message);
}
