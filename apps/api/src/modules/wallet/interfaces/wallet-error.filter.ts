import { type ArgumentsHost, Catch, type ExceptionFilter, HttpException, HttpStatus } from '@nestjs/common';
import type { Response } from 'express';
import {
  CannotGiftYourselfError,
  GiftBlockedError,
  GiftIdConflictError,
  GiftLiveUnavailableError,
  GiftVideoUnavailableError,
  InsufficientBalanceError,
  TooManyGiftsError,
  UnknownGiftError,
  WalletError,
} from '../domain/wallet.errors';

// Traduit les erreurs métier des cadeaux en réponses HTTP (ADR-003, ADR-050). 429 porte l'en-tête Retry-After.
@Catch(WalletError)
export class WalletErrorFilter implements ExceptionFilter {
  catch(error: WalletError, host: ArgumentsHost) {
    const response = host.switchToHttp().getResponse<Response>();
    if (error instanceof TooManyGiftsError) response.setHeader('Retry-After', String(error.retryAfterSeconds));
    const status = statusOf(error);
    response.status(status).json({ statusCode: status, message: error.message, error: ERROR_NAMES[status] });
  }
}

function statusOf(error: WalletError): HttpStatus {
  if (error instanceof UnknownGiftError || error instanceof CannotGiftYourselfError) return HttpStatus.BAD_REQUEST;
  if (error instanceof InsufficientBalanceError) return HttpStatus.PAYMENT_REQUIRED;
  if (error instanceof GiftBlockedError) return HttpStatus.FORBIDDEN;
  if (error instanceof GiftVideoUnavailableError || error instanceof GiftLiveUnavailableError) return HttpStatus.NOT_FOUND;
  if (error instanceof GiftIdConflictError) return HttpStatus.CONFLICT;
  if (error instanceof TooManyGiftsError) return HttpStatus.TOO_MANY_REQUESTS;
  throw new HttpException('Erreur interne', HttpStatus.INTERNAL_SERVER_ERROR);
}

const ERROR_NAMES: Partial<Record<HttpStatus, string>> = {
  [HttpStatus.BAD_REQUEST]: 'Bad Request',
  [HttpStatus.PAYMENT_REQUIRED]: 'Payment Required',
  [HttpStatus.FORBIDDEN]: 'Forbidden',
  [HttpStatus.NOT_FOUND]: 'Not Found',
  [HttpStatus.CONFLICT]: 'Conflict',
  [HttpStatus.TOO_MANY_REQUESTS]: 'Too Many Requests',
};
