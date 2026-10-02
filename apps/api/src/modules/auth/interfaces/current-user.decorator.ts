import { createParamDecorator, ExecutionContext } from '@nestjs/common';

// Ce que JwtStrategy.validate() place dans `request.user`.
export interface AuthenticatedUser {
  userId: string;
}

// Utilisateur connecté. Toujours défini sur une route protégée ; sur une route @Public(),
// `undefined` en mode invité : typer alors le paramètre `AuthenticatedUser | undefined`.
export const CurrentUser = createParamDecorator(
  (_data: unknown, context: ExecutionContext): AuthenticatedUser | undefined =>
    context.switchToHttp().getRequest<{ user?: AuthenticatedUser }>().user,
);
