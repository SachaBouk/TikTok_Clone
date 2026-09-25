import {
  ArgumentsHost,
  BadRequestException,
  Catch,
  ConflictException,
  ExceptionFilter,
  HttpException,
  NotFoundException,
} from '@nestjs/common';
import type { Response } from 'express';
import { AvatarNotUploadedError, InvalidAvatarError, InvalidProfileError, UserError, UsernameTakenError } from '../domain/user.errors';

// Traduit les erreurs métier du module en réponses HTTP (ADR-003).
@Catch(UserError)
export class UserErrorFilter implements ExceptionFilter {
  catch(error: UserError, host: ArgumentsHost) {
    const exception = toHttpException(error);
    host.switchToHttp().getResponse<Response>().status(exception.getStatus()).json(exception.getResponse());
  }
}

function toHttpException(error: UserError): HttpException {
  if (error instanceof UsernameTakenError) return new ConflictException(error.message);
  if (error instanceof InvalidProfileError || error instanceof InvalidAvatarError || error instanceof AvatarNotUploadedError) {
    return new BadRequestException(error.message);
  }
  // UserNotFoundError
  return new NotFoundException(error.message);
}
