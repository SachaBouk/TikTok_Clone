import { Injectable } from '@nestjs/common';
import { SignJWT } from 'jose';
import {
  CrossLiveUnavailableError,
  PARTICIPANT_TOKEN_TTL_SECONDS,
  ParticipantTokenSigner,
  type ParticipantClaims,
} from '../domain/participant-token';
import type { CrossLiveConfig } from './crosslive.config';

// Signe le Jeton de Participant en HS256 avec le secret de l'App membre (ADR-079).
@Injectable()
export class JoseParticipantTokenSigner extends ParticipantTokenSigner {
  private readonly key: Uint8Array | null;

  constructor(private readonly config: CrossLiveConfig) {
    super();
    this.key = config.secret ? new TextEncoder().encode(config.secret) : null;
  }

  get available(): boolean {
    return this.key !== null;
  }

  async sign(claims: ParticipantClaims): Promise<string> {
    if (!this.key) throw new CrossLiveUnavailableError();
    const payload: Record<string, string> = { name: claims.name };
    if (claims.picture) payload.picture = claims.picture;
    const now = Math.floor(Date.now() / 1000);
    return new SignJWT(payload)
      .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
      .setIssuer(this.config.appId)
      .setSubject(claims.sub)
      .setIssuedAt(now)
      .setExpirationTime(now + PARTICIPANT_TOKEN_TTL_SECONDS)
      .sign(this.key);
  }
}
