import 'server-only';
import type { AdminSuspendUserDto, AdminUserDto, AdminUserPageDto } from '@repo/shared';
import { apiRequest, orNull } from '@/lib/api-client';

export function listUsers(filter: { q?: string; cursor?: string }): Promise<AdminUserPageDto> {
  return apiRequest('GET', '/admin/users', { q: filter.q, cursor: filter.cursor, limit: 25 });
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
