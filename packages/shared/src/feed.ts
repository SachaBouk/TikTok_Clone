import type { AuthorStoryDto } from './stories.js';
import type { UserSummaryDto } from './users.js';

// Feed principal (ADR-016) : vidéos publiées, dans un ordre aléatoire propre à chaque session de scroll.

// État propre à l'utilisateur connecté, pour afficher les boutons (cœur plein, « Suivi »…).
export interface FeedViewerStateDto {
  liked: boolean;
  favorited: boolean;
  reposted: boolean;
  followingAuthor: boolean;
}

export interface FeedItemDto {
  // Identifiant de la vidéo.
  id: string;
  description: string | null;
  // Manifeste HLS à donner à AVPlayer (ADR-008).
  hlsUrl: string;
  thumbnailUrl: string;
  createdAt: string;
  viewsCount: number;
  likesCount: number;
  commentsCount: number;
  favoritesCount: number;
  sharesCount: number;
  repostsCount: number;
  author: UserSummaryDto;
  // Absent en mode invité (plutôt que null : OpenAPI 3.0 ne sait pas décrire une référence nullable,
  // et le client Swift en ferait une structure enveloppe).
  viewer?: FeedViewerStateDto;
  // Anneau autour de l'avatar (ADR-051) : absent si l'auteur n'a pas de story visible.
  authorStory?: AuthorStoryDto;
  // Historique de visionnage seulement (ADR-057) : dernière vue de la vidéo par le compte connecté.
  viewedAt?: string;
}

export interface FeedPageDto {
  items: FeedItemDto[];
  // À renvoyer tel quel pour la page suivante ; null à la fin du feed (repartir sans curseur pour un nouvel ordre).
  nextCursor: string | null;
}

// Grilles du profil : vidéos publiées d'un compte, ses republications, ses favoris. Même élément que le feed :
// l'app les ouvre dans le même lecteur.
export interface VideoPageDto {
  items: FeedItemDto[];
  // À renvoyer tel quel pour la page suivante ; null s'il n'y en a plus.
  nextCursor: string | null;
}
