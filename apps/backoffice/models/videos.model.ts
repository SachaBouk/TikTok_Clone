import 'server-only';
import type { AdminVideoDto, AdminVideoPageDto, VideoStatus } from '@repo/shared';
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

// Suppression réelle (cascade, fichiers nettoyés par l'API), quel que soit le statut.
export function deleteVideo(id: string): Promise<void> {
  return apiRequest('DELETE', `/admin/videos/${encodeURIComponent(id)}`);
}
