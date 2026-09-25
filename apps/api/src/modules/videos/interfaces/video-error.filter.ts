import { ArgumentsHost, BadRequestException, Catch, ConflictException, ExceptionFilter, HttpException, NotFoundException } from '@nestjs/common';
import type { Response } from 'express';
import { VideoError, VideoNotAwaitingUploadError, VideoNotFoundError } from '../domain/video.errors';

// Traduit les erreurs métier du module en réponses HTTP (ADR-003).
@Catch(VideoError)
export class VideoErrorFilter implements ExceptionFilter {
  catch(error: VideoError, host: ArgumentsHost) {
    const exception = toHttpException(error);
    host.switchToHttp().getResponse<Response>().status(exception.getStatus()).json(exception.getResponse());
  }
}

function toHttpException(error: VideoError): HttpException {
  if (error instanceof VideoNotFoundError) return new NotFoundException(error.message);
  if (error instanceof VideoNotAwaitingUploadError) return new ConflictException(error.message);
  // UnsupportedVideoTypeError, VideoTooLargeError, UploadIncompleteError
  return new BadRequestException(error.message);
}
