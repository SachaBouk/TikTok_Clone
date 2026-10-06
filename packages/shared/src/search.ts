import type { FollowViewerStateDto } from './interactions.js';
import type { UserSummaryDto } from './users.js';

// Recherche de comptes et hashtags (ADR-049).

export interface AccountSearchItemDto {
  user: UserSummaryDto;
  followersCount: number;
  // Relation avec le compte connecté (bouton « Suivre ») ; absent en mode invité.
  viewer?: FollowViewerStateDto;
}

export interface AccountSearchPageDto {
  // Pseudo identique, pseudo qui commence par le texte cherché, puis abonnés décroissants.
  items: AccountSearchItemDto[];
  // À renvoyer tel quel pour la page suivante ; null s'il n'y en a plus (100 résultats au plus).
  nextCursor: string | null;
}

export interface HashtagDto {
  // Sans « # », en minuscules.
  name: string;
  // Vidéos publiées portant ce hashtag.
  videosCount: number;
}

export interface HashtagListDto {
  items: HashtagDto[];
}
