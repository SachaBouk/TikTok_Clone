import type { RealtimeSession } from './realtime';

// Vérifie l'access token présenté au handshake (fourni par le module auth, ADR-010).
export abstract class AccessTokenVerifier {
  // Null si le token est absent, invalide ou expiré.
  abstract verify(accessToken: string): Promise<RealtimeSession | null>;
}
