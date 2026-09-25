import { applyDecorators, SetMetadata } from '@nestjs/common';
import { ApiExtension } from '@nestjs/swagger';

export const IS_PUBLIC_KEY = 'isPublic';
// Lu par buildOpenApiDocument pour retirer l'exigence d'authentification de la route dans la spec.
export const OPENAPI_PUBLIC_EXTENSION = 'x-public';

// Toutes les routes exigent un access token (garde globale JwtAuthGuard), sauf celles marquées @Public().
// Mode invité (ADR-010) : les routes de lecture accessibles sans compte (feed, profils) doivent être publiques.
// Le même décorateur alimente la garde et la spec OpenAPI : les deux ne peuvent pas diverger.
export const Public = () => applyDecorators(SetMetadata(IS_PUBLIC_KEY, true), ApiExtension(OPENAPI_PUBLIC_EXTENSION, true));
