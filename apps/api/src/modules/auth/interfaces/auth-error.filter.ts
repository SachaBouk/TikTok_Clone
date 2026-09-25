import { ArgumentsHost, Catch, ConflictException, ExceptionFilter, HttpException, UnauthorizedException } from '@nestjs/common';
import type { Response } from 'express';
import { AuthError, EmailAlreadyUsedError, UsernameAlreadyUsedError } from '../domain/auth.errors';

// Traduit les erreurs métier du module en réponses HTTP (ADR-003 : pas de logique HTTP dans le domaine).
@Catch(AuthError)
export class AuthErrorFilter implements ExceptionFilter {
  catch(error: AuthError, host: ArgumentsHost) {
    const exception = toHttpException(error);
    host.switchToHttp().getResponse<Response>().status(exception.getStatus()).json(exception.getResponse());
  }
}

function toHttpException(error: AuthError): HttpException {
  if (error instanceof EmailAlreadyUsedError || error instanceof UsernameAlreadyUsedError) {
    return new ConflictException(error.message);
  }
  // InvalidCredentialsError, InvalidRefreshTokenError, InvalidAppleTokenError
  return new UnauthorizedException(error.message);
}
