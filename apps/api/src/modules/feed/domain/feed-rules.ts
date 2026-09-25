// Règles du feed principal (ADR-016 : ordre aléatoire, sans recommandation ; ADR-014 : cache Redis).

// La « photo » du catalogue (identifiants des vidéos publiées) est partagée par tous et renouvelée
// au plus toutes les 5 minutes : une vidéo publiée apparaît dans les nouvelles sessions sous 5 minutes.
export const SNAPSHOT_REFRESH_SECONDS = 5 * 60;

// Une photo reste lisible 2 h : durée maximale d'une session de scroll avant de repartir sur un nouvel ordre.
export const SNAPSHOT_TTL_SECONDS = 2 * 60 * 60;

// Taille maximale du catalogue mélangé (les vidéos les plus récentes). À revoir au-delà du MVP.
export const CATALOG_LIMIT = 10_000;

export const DEFAULT_PAGE_SIZE = 10;
export const MAX_PAGE_SIZE = 20;

// Grilles du profil (vidéos, republications, favoris d'un compte) : 3 colonnes.
export const DEFAULT_GRID_PAGE_SIZE = 21;
export const MAX_GRID_PAGE_SIZE = 60;
