import 'server-only';
import type { ReportReason } from '@repo/shared';
import { apiRequest } from '@/lib/api-client';

// Arrêt d'un live signalé (ADR-053) : la salle est fermée, son auteur est prévenu avec le motif.
export function deleteLive(id: string, reason: ReportReason): Promise<void> {
  return apiRequest('DELETE', `/admin/lives/${encodeURIComponent(id)}`, { reason });
}
