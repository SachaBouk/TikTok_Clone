import { ApiTooManyRequestsResponse } from '@nestjs/swagger';
import { ErrorResponse } from '../openapi/error.response';

// Réponse 429 d'une route limitée (ADR-030, ADR-039), avec l'en-tête Retry-After documenté : le client Swift généré
// l'expose (`headers.retryAfter`) et chaque 429 devient un cas de la réponse.
export function ApiTooManyRequests(description: string): MethodDecorator {
  return ApiTooManyRequestsResponse({
    type: ErrorResponse,
    description: `${description} : réessayer après le délai de l’en-tête Retry-After (secondes).`,
    headers: { 'Retry-After': { description: 'Secondes à attendre avant de réessayer.', schema: { type: 'integer', minimum: 1 } } },
  });
}
