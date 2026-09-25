import { ExecutionContext, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AuthGuard } from '@nestjs/passport';
import type { Request } from 'express';
import { IS_PUBLIC_KEY } from './public.decorator';

// Garde globale (APP_GUARD) : sécurisé par défaut, les routes publiques sont l'exception explicite.
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  constructor(private readonly reflector: Reflector) {
    super();
  }

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!isPublic) return super.canActivate(context) as Promise<boolean>;

    // Route publique : on identifie quand même l'utilisateur s'il envoie un token (ex. l'auteur qui
    // consulte sa vidéo en cours de traitement). Sans token, ou avec un token invalide : mode invité.
    if (!context.switchToHttp().getRequest<Request>().headers.authorization) return true;
    try {
      await super.canActivate(context);
    } catch {
      // Token invalide ou expiré sur une route publique : traité comme un invité.
    }
    return true;
  }
}
