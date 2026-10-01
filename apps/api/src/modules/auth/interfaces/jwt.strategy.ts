import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { AuthService } from '../application/auth.service';
import { AuthConfig } from '../auth.config';
import type { AuthenticatedUser } from './current-user.decorator';

// Valide l'access token (en-tête `Authorization: Bearer …`) : signature, algorithme et expiration, puis refuse
// celui d'un compte suspendu (ADR-037, registre Redis) : 401 sur une route protégée, invité sur une route publique.
@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(
    config: AuthConfig,
    private readonly auth: AuthService,
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      secretOrKey: config.jwtAccessSecret,
      algorithms: ['HS256'],
    });
  }

  async validate(payload: { sub?: string }): Promise<AuthenticatedUser> {
    if (!payload.sub || (await this.auth.isSuspended(payload.sub))) throw new UnauthorizedException();
    return { userId: payload.sub };
  }
}
