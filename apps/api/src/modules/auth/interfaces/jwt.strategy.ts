import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { AuthConfig } from '../auth.config';
import type { AuthenticatedUser } from './current-user.decorator';

// Valide l'access token (en-tête `Authorization: Bearer …`) : signature, algorithme et expiration.
@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(config: AuthConfig) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      secretOrKey: config.jwtAccessSecret,
      algorithms: ['HS256'],
    });
  }

  validate(payload: { sub?: string }): AuthenticatedUser {
    if (!payload.sub) throw new UnauthorizedException();
    return { userId: payload.sub };
  }
}
