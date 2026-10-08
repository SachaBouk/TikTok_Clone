import 'server-only';
import type { ReportReason } from '@repo/shared';
import { apiRequest } from '@/lib/api-client';

// Retrait d'une story signalée (ADR-051), quel que soit son statut ; son auteur est prévenu avec le motif.
export function deleteStory(id: string, reason: ReportReason): Promise<void> {
  return apiRequest('DELETE', `/admin/stories/${encodeURIComponent(id)}`, { reason });
}
