import type { UserSummaryDto } from './users.js';
import type { VideoVisibility } from './videos.js';

// Collection de favoris (ADR-072) : nom, visibilité, nombre de vidéos, image (miniature de la dernière vidéo visible du
// lecteur), titulaire.
export interface CollectionDto {
  id: string;
  name: string;
  visibility: VideoVisibility;
  videosCount: number;
  coverUrl: string | null;
  owner: UserSummaryDto;
  createdAt: string;
  updatedAt: string;
  // `GET /users/me/collections?videoId=` : la collection contient-elle cette vidéo ? Absent sans `videoId`.
  containsVideo?: boolean;
}

export interface CollectionListDto {
  items: CollectionDto[];
}
