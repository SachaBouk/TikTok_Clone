import 'server-only';
import type { AdminVideoDto, AdminVideoPageDto, ReportReason, VideoStatus } from '@repo/shared';
import { apiRequest, orNull } from '@/lib/api-client';

export interface VideoFilter {
  status?: VideoStatus;
  userId?: string;
  cursor?: string;
  limit?: number;
}

export function listVideos(filter: VideoFilter): Promise<AdminVideoPageDto> {
  return apiRequest('GET', '/admin/videos', { status: filter.status, userId: filter.userId, cursor: filter.cursor, limit: filter.limit ?? 25 });
}

export function getVideo(id: string): Promise<AdminVideoDto | null> {
  return orNull(apiRequest('GET', `/admin/videos/${encodeURIComponent(id)}`));
}

// Suppression réelle (cascade, fichiers nettoyés par l'API), quel que soit le statut. Le motif est annoncé à l'auteur.
export function deleteVideo(id: string, reason: ReportReason): Promise<void> {
  return apiRequest('DELETE', `/admin/videos/${encodeURIComponent(id)}`, { reason });
}
