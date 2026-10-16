import type { VideoStatus, VideoVisibility } from '@repo/shared';
import { Badge } from '@/components/ui/badge';

export const VIDEO_STATUS_LABELS: Record<VideoStatus, string> = {
  uploading: 'Envoi en cours',
  processing: 'En traitement',
  ready: 'Publiée',
  failed: 'Échec',
};

const VARIANTS: Record<VideoStatus, 'default' | 'secondary' | 'destructive' | 'outline'> = {
  uploading: 'outline',
  processing: 'secondary',
  ready: 'default',
  failed: 'destructive',
};

export function VideoStatusBadge({ status }: { status: VideoStatus }) {
  return <Badge variant={VARIANTS[status]}>{VIDEO_STATUS_LABELS[status]}</Badge>;
}

// Vidéo privée (ADR-061) : visible de son seul auteur dans l'app.
export function VideoVisibilityBadge({ visibility }: { visibility: VideoVisibility }) {
  return visibility === 'private' ? <Badge variant="outline">Privée</Badge> : null;
}
