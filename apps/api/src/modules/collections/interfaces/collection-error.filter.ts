import { ArgumentsHost, BadRequestException, Catch, ConflictException, ExceptionFilter, HttpException, NotFoundException } from '@nestjs/common';
import type { Response } from 'express';
import { CollectionError, CollectionNotFoundError, TooManyCollectionsError } from '../domain/collection.errors';

// Traduit les erreurs métier du module en réponses HTTP (ADR-003).
@Catch(CollectionError)
export class CollectionErrorFilter implements ExceptionFilter {
  catch(error: CollectionError, host: ArgumentsHost) {
    const response = host.switchToHttp().getResponse<Response>();
    const exception = toHttpException(error);
    response.status(exception.getStatus()).json(exception.getResponse());
  }
}

function toHttpException(error: CollectionError): HttpException {
  if (error instanceof CollectionNotFoundError) return new NotFoundException(error.message);
  if (error instanceof TooManyCollectionsError) return new ConflictException(error.message);
  // InvalidCollectionNameError, TooManyCollectionVideosError
  return new BadRequestException(error.message);
}
