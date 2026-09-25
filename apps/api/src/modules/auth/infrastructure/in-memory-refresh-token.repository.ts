import { randomUUID } from 'node:crypto';
import { NewRefreshToken, RefreshToken, RefreshTokenRepository } from '../domain/refresh-token.repository';

// Adaptateur en mémoire pour les tests.
export class InMemoryRefreshTokenRepository extends RefreshTokenRepository {
  readonly tokens: (RefreshToken & { tokenHash: string })[] = [];

  async create(token: NewRefreshToken): Promise<void> {
    this.tokens.push({ ...token, id: randomUUID(), revokedAt: null });
  }

  async findByHash(tokenHash: string): Promise<RefreshToken | null> {
    const token = this.tokens.find((t) => t.tokenHash === tokenHash);
    return token ? { ...token } : null;
  }

  async revoke(id: string, at: Date): Promise<boolean> {
    const token = this.tokens.find((t) => t.id === id && t.revokedAt === null);
    if (!token) return false;
    token.revokedAt = at;
    return true;
  }

  async revokeFamily(familyId: string, at: Date): Promise<void> {
    for (const token of this.tokens) {
      if (token.familyId === familyId && token.revokedAt === null) token.revokedAt = at;
    }
  }
}
