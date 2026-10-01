export interface RefreshToken {
  id: string;
  userId: string;
  familyId: string;
  expiresAt: Date;
  revokedAt: Date | null;
}

export interface NewRefreshToken {
  userId: string;
  familyId: string;
  tokenHash: string;
  expiresAt: Date;
}

export abstract class RefreshTokenRepository {
  abstract create(token: NewRefreshToken): Promise<void>;
  abstract findByHash(tokenHash: string): Promise<RefreshToken | null>;
  // Révoque le token s'il ne l'est pas déjà, de façon atomique.
  // Renvoie false si un autre appel l'a révoqué avant (deux rotations concurrentes du même token).
  abstract revoke(id: string, at: Date): Promise<boolean>;
  abstract revokeFamily(familyId: string, at: Date): Promise<void>;
  // Toutes les sessions du compte (suspension, ADR-037).
  abstract revokeAllForUser(userId: string, at: Date): Promise<void>;
}
