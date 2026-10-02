import 'server-only';
import type { AdminSuspendUserDto, AdminUserDto, AdminUserPageDto } from '@repo/shared';
import { apiRequest, orNull } from '@/lib/api-client';

// `suspended` : comptes suspendus seulement (ADR-037), du plus récemment suspendu au plus ancien ; `q` est alors ignoré.
export function listUsers(filter: { q?: string; cursor?: string; suspended?: boolean }): Promise<AdminUserPageDto> {
  return apiRequest('GET', '/admin/users', { q: filter.q, cursor: filter.cursor, suspended: filter.suspended ? 'true' : undefined, limit: 25 });
}

export function getUser(id: string): Promise<AdminUserDto | null> {
  return orNull(apiRequest('GET', `/admin/users/${encodeURIComponent(id)}`));
}

// Suspension (ADR-037) : connexion refusée, contenus masqués, jusqu'à la levée.
export function suspendUser(id: string, reason: string): Promise<AdminUserDto> {
  const body: AdminSuspendUserDto = { reason };
  return apiRequest('PUT', `/admin/users/${encodeURIComponent(id)}/suspension`, {}, body);
}

export function liftSuspension(id: string): Promise<AdminUserDto> {
  return apiRequest('DELETE', `/admin/users/${encodeURIComponent(id)}/suspension`);
}
