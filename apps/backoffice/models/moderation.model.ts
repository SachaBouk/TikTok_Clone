import 'server-only';
import type { AdminModerationActionPageDto } from '@repo/shared';
import { apiRequest } from '@/lib/api-client';

// Journal de modération (ADR-038), du plus récent au plus ancien ; `userId` : actions sur ce compte.
export function listModerationActions(filter: { userId?: string; cursor?: string }): Promise<AdminModerationActionPageDto> {
  return apiRequest('GET', '/admin/moderation-actions', { userId: filter.userId, cursor: filter.cursor, limit: 25 });
}
