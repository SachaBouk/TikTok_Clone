import {
  ArgumentsHost,
  BadRequestException,
  Catch,
  ConflictException,
  ExceptionFilter,
  ForbiddenException,
  HttpException,
  HttpStatus,
  UnauthorizedException,
} from '@nestjs/common';
import type { Response } from 'express';
import {
  AccountSuspendedError,
  AuthError,
  CannotSuspendAdminError,
  EmailAlreadyUsedError,
  InvalidSuspensionReasonError,
  TooManyLoginAttemptsError,
  UsernameAlreadyUsedError,
} from '../domain/auth.errors';

// Traduit les erreurs métier du module en réponses HTTP (ADR-003 : pas de logique HTTP dans le domaine).
// 429 porte l'en-tête Retry-After.
@Catch(AuthError)
export class AuthErrorFilter implements ExceptionFilter {
  catch(error: AuthError, host: ArgumentsHost) {
    const response = host.switchToHttp().getResponse<Response>();
    if (error instanceof TooManyLoginAttemptsError) response.setHeader('Retry-After', String(error.retryAfterSeconds));
    const exception = toHttpException(error);
    response.status(exception.getStatus()).json(exception.getResponse());
  }
}

function toHttpException(error: AuthError): HttpException {
  if (error instanceof TooManyLoginAttemptsError) {
    return new HttpException({ statusCode: HttpStatus.TOO_MANY_REQUESTS, message: error.message, error: 'Too Many Requests' }, HttpStatus.TOO_MANY_REQUESTS);
  }
  if (error instanceof EmailAlreadyUsedError || error instanceof UsernameAlreadyUsedError || error instanceof CannotSuspendAdminError) {
    return new ConflictException(error.message);
  }
  if (error instanceof AccountSuspendedError) return new ForbiddenException(error.message);
  if (error instanceof InvalidSuspensionReasonError) return new BadRequestException(error.message);
  // InvalidCredentialsError, InvalidRefreshTokenError, InvalidAppleTokenError
  return new UnauthorizedException(error.message);
}
