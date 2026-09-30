import 'server-only';
import type { AdminWalletTransactionPageDto } from '@repo/shared';
import { apiRequest } from '@/lib/api-client';

// Model du journal des jetons (ADR-009, ADR-021) : mouvements appliqués aux soldes, clients inconnus compris.
export interface WalletTransactionFilter {
  userId?: string;
  // Seulement les mouvements d'un client inconnu de l'API, à rapprocher.
  unmatched?: boolean;
  cursor?: string;
  limit?: number;
}

export function listWalletTransactions(filter: WalletTransactionFilter): Promise<AdminWalletTransactionPageDto> {
  return apiRequest('GET', '/admin/wallet-transactions', {
    userId: filter.userId,
    unmatched: filter.unmatched ? 'true' : undefined,
    cursor: filter.cursor,
    limit: filter.limit ?? 25,
  });
}
