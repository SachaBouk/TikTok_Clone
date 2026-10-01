import 'server-only';
import type { AdminCommentPageDto, ReportReason } from '@repo/shared';
import { apiRequest } from '@/lib/api-client';

export interface CommentFilter {
  videoId?: string;
  userId?: string;
  cursor?: string;
  limit?: number;
}

export function listComments(filter: CommentFilter): Promise<AdminCommentPageDto> {
  return apiRequest('GET', '/admin/comments', { videoId: filter.videoId, userId: filter.userId, cursor: filter.cursor, limit: filter.limit ?? 25 });
}

// Le motif est annoncé à l'auteur.
export function deleteComment(id: string, reason: ReportReason): Promise<void> {
  return apiRequest('DELETE', `/admin/comments/${encodeURIComponent(id)}`, { reason });
}
