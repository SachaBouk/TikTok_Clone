import { ArgumentsHost, BadRequestException, Catch, ConflictException, ExceptionFilter, HttpException, HttpStatus, NotFoundException } from '@nestjs/common';
import type { Response } from 'express';
import { TooManyUploadsError, VideoError, VideoNotAwaitingUploadError, VideoNotFoundError } from '../domain/video.errors';

// Traduit les erreurs métier du module en réponses HTTP (ADR-003). 429 porte l'en-tête Retry-After.
@Catch(VideoError)
export class VideoErrorFilter implements ExceptionFilter {
  catch(error: VideoError, host: ArgumentsHost) {
    const response = host.switchToHttp().getResponse<Response>();
    if (error instanceof TooManyUploadsError) response.setHeader('Retry-After', String(error.retryAfterSeconds));
    const exception = toHttpException(error);
    response.status(exception.getStatus()).json(exception.getResponse());
  }
}

function toHttpException(error: VideoError): HttpException {
  if (error instanceof TooManyUploadsError) {
    return new HttpException({ statusCode: HttpStatus.TOO_MANY_REQUESTS, message: error.message, error: 'Too Many Requests' }, HttpStatus.TOO_MANY_REQUESTS);
  }
  if (error instanceof VideoNotFoundError) return new NotFoundException(error.message);
  if (error instanceof VideoNotAwaitingUploadError) return new ConflictException(error.message);
  // UnsupportedVideoTypeError, VideoTooLargeError, UploadIncompleteError
  return new BadRequestException(error.message);
}
