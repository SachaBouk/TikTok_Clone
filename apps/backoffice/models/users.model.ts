import 'server-only';
import type { AdminUserDto, AdminUserPageDto } from '@repo/shared';
import { apiRequest, orNull } from '@/lib/api-client';

export function listUsers(filter: { q?: string; cursor?: string }): Promise<AdminUserPageDto> {
  return apiRequest('GET', '/admin/users', { q: filter.q, cursor: filter.cursor, limit: 25 });
}

export function getUser(id: string): Promise<AdminUserDto | null> {
  return orNull(apiRequest('GET', `/admin/users/${encodeURIComponent(id)}`));
}
