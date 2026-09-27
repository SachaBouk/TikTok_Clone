import { applyDecorators, SetMetadata } from '@nestjs/common';
import { ApiForbiddenResponse } from '@nestjs/swagger';
import { ErrorResponse } from '../../../openapi/error.response';

export const IS_ADMIN_ONLY_KEY = 'isAdminOnly';

// Routes du backoffice (ADR-004) : access token exigé, et compte au rôle `admin`. Vérifié par la garde
// globale JwtAuthGuard, qui relit le rôle en base à chaque requête (un rôle retiré prend effet aussitôt).
// Sans ce rôle : 403, documenté dans la spec par le même décorateur.
export const AdminOnly = () =>
  applyDecorators(
    SetMetadata(IS_ADMIN_ONLY_KEY, true),
    ApiForbiddenResponse({ type: ErrorResponse, description: 'Compte sans rôle administrateur.' }),
  );
