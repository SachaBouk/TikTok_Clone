import {
  ArgumentsHost,
  BadRequestException,
  Catch,
  ConflictException,
  ExceptionFilter,
  GoneException,
  HttpException,
  NotFoundException,
} from '@nestjs/common';
import type { Response } from 'express';
import {
  AvatarNotUploadedError,
  InvalidAvatarError,
  InvalidProfileError,
  ProfileSuspendedError,
  UnknownInterestError,
  UserError,
  UsernameTakenError,
} from '../domain/user.errors';

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
  if (
    error instanceof InvalidProfileError ||
    error instanceof InvalidAvatarError ||
    error instanceof AvatarNotUploadedError ||
    error instanceof UnknownInterestError
  ) {
    return new BadRequestException(error.message);
  }
  if (error instanceof ProfileSuspendedError) return new GoneException(error.message);
  // UserNotFoundError
  return new NotFoundException(error.message);
}
