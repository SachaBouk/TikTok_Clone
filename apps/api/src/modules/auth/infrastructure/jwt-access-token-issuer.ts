import { Injectable } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { AccessTokenIssuer, type VerifiedAccessToken } from '../domain/access-token-issuer';

// La clé et la durée de validité sont configurées sur le JwtModule (auth.module.ts).
@Injectable()
export class JwtAccessTokenIssuer extends AccessTokenIssuer {
  constructor(private readonly jwt: JwtService) {
    super();
  }

  issue(userId: string): Promise<string> {
    return this.jwt.signAsync({ sub: userId });
  }

  // Mêmes règles que JwtStrategy : HS256 uniquement, signature et expiration vérifiées.
  async verify(token: string): Promise<VerifiedAccessToken | null> {
    try {
      const payload = await this.jwt.verifyAsync<{ sub?: unknown; exp?: unknown }>(token, { algorithms: ['HS256'] });
      if (typeof payload.sub !== 'string' || typeof payload.exp !== 'number') return null;
      return { userId: payload.sub, expiresAt: new Date(payload.exp * 1000) };
    } catch {
      return null;
    }
  }
}
