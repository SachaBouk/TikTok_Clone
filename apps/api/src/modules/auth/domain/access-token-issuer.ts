// Access token : JWT de courte durée (ADR-010). Émis à la connexion, vérifié hors HTTP
// (handshake WebSocket, ADR-011) ; sur les routes HTTP, c'est la stratégie Passport qui le vérifie.
export interface VerifiedAccessToken {
  userId: string;
  expiresAt: Date;
}

export abstract class AccessTokenIssuer {
  abstract issue(userId: string): Promise<string>;
  // Null si le token est invalide, falsifié ou expiré.
  abstract verify(token: string): Promise<VerifiedAccessToken | null>;
}
