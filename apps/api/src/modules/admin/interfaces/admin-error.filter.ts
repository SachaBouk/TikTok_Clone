import { ArgumentsHost, Catch, ConflictException, ExceptionFilter, NotFoundException } from '@nestjs/common';
import type { Response } from 'express';
import { AdminActionRefusedError, AdminError } from '../domain/admin.errors';

// Traduit les erreurs métier du module en réponses HTTP (ADR-003).
@Catch(AdminError)
export class AdminErrorFilter implements ExceptionFilter {
  catch(error: AdminError, host: ArgumentsHost) {
    // AdminTargetNotFoundError : 404 ; AdminActionRefusedError : 409.
    const exception = error instanceof AdminActionRefusedError ? new ConflictException(error.message) : new NotFoundException(error.message);
    host.switchToHttp().getResponse<Response>().status(exception.getStatus()).json(exception.getResponse());
  }
}
