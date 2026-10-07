import 'server-only';
import type { AdminGiftPageDto } from '@repo/shared';
import { apiRequest } from '@/lib/api-client';

// Model du journal des cadeaux (ADR-050) : envoyés et reçus, comptes et vidéos supprimés compris. Lecture seule.
export interface GiftFilter {
  // Cadeaux envoyés ou reçus par ce compte.
  userId?: string;
  cursor?: string;
  limit?: number;
}

export function listGifts(filter: GiftFilter): Promise<AdminGiftPageDto> {
  return apiRequest('GET', '/admin/gifts', { userId: filter.userId, cursor: filter.cursor, limit: filter.limit ?? 25 });
}
