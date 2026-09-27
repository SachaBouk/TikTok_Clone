import { ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AuthGuard } from '@nestjs/passport';
import type { Request } from 'express';
import { AuthService } from '../application/auth.service';
import { IS_ADMIN_ONLY_KEY } from './admin-only.decorator';
import type { AuthenticatedUser } from './current-user.decorator';
import { IS_PUBLIC_KEY } from './public.decorator';

// Garde globale (APP_GUARD) : sécurisé par défaut, les routes publiques sont l'exception explicite.
// Les routes @AdminOnly() exigent en plus le rôle administrateur (ADR-004).
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  constructor(
    private readonly reflector: Reflector,
    private readonly authService: AuthService,
  ) {
    super();
  }

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const targets = [context.getHandler(), context.getClass()];
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, targets);
    const request = context.switchToHttp().getRequest<Request>();
    if (!isPublic) {
      await super.canActivate(context);
      if (this.reflector.getAllAndOverride<boolean>(IS_ADMIN_ONLY_KEY, targets)) {
        const user = request.user as AuthenticatedUser;
        if (!(await this.authService.isAdmin(user.userId))) throw new ForbiddenException('Accès réservé aux administrateurs');
      }
      return true;
    }

    // Route publique : on identifie quand même l'utilisateur s'il envoie un token (ex. l'auteur qui
    // consulte sa vidéo en cours de traitement). Sans token, ou avec un token invalide : mode invité.
    if (!request.headers.authorization) return true;
    try {
      await super.canActivate(context);
    } catch {
      // Token invalide ou expiré sur une route publique : traité comme un invité.
    }
    return true;
  }
}
