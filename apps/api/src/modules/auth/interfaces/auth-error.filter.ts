import { ArgumentsHost, Catch, ConflictException, ExceptionFilter, HttpException, HttpStatus, UnauthorizedException } from '@nestjs/common';
import type { Response } from 'express';
import { AuthError, EmailAlreadyUsedError, TooManyLoginAttemptsError, UsernameAlreadyUsedError } from '../domain/auth.errors';

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
  if (error instanceof EmailAlreadyUsedError || error instanceof UsernameAlreadyUsedError) {
    return new ConflictException(error.message);
  }
  // InvalidCredentialsError, InvalidRefreshTokenError, InvalidAppleTokenError
  return new UnauthorizedException(error.message);
}
