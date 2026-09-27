import { ArgumentsHost, Catch, ExceptionFilter, NotFoundException } from '@nestjs/common';
import type { Response } from 'express';
import { AdminError } from '../domain/admin.errors';

// Traduit les erreurs métier du module en réponses HTTP (ADR-003).
@Catch(AdminError)
export class AdminErrorFilter implements ExceptionFilter {
  catch(error: AdminError, host: ArgumentsHost) {
    // AdminTargetNotFoundError
    const exception = new NotFoundException(error.message);
    host.switchToHttp().getResponse<Response>().status(exception.getStatus()).json(exception.getResponse());
  }
}
