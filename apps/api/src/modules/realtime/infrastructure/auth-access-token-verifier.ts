import { Injectable } from '@nestjs/common';
import { AuthService } from '../../auth/application/auth.service';
import { AccessTokenVerifier } from '../domain/access-token-verifier';
import type { RealtimeSession } from '../domain/realtime';

// Délègue au module auth, seul détenteur des règles de l'access token (ADR-010, ADR-003).
@Injectable()
export class AuthAccessTokenVerifier extends AccessTokenVerifier {
  constructor(private readonly auth: AuthService) {
    super();
  }

  verify(accessToken: string): Promise<RealtimeSession | null> {
    return this.auth.verifyAccessToken(accessToken);
  }
}
