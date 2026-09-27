import 'server-only';
import type { AdminStatsDto } from '@repo/shared';
import { apiRequest } from '@/lib/api-client';

// Tableau de bord : comptages internes de l'API (les analyses d'usage restent dans PostHog, ADR-013).
export function getStats(): Promise<AdminStatsDto> {
  return apiRequest('GET', '/admin/stats');
}
