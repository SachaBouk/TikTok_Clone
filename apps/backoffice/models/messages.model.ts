import 'server-only';
import type { ReportReason } from '@repo/shared';
import { apiRequest } from '@/lib/api-client';

// Retrait d'un message signalé (ADR-038), pour les deux participants. Le backoffice ne lit jamais les conversations :
// seul le texte du message signalé, copié dans le signalement, est visible.
export function deleteMessage(id: string, reason: ReportReason): Promise<void> {
  return apiRequest('DELETE', `/admin/messages/${encodeURIComponent(id)}`, { reason });
}
