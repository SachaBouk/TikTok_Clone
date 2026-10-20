// Cycle de vie (ADR-008) : uploading → processing → ready / failed.
export type VideoStatus = 'uploading' | 'processing' | 'ready' | 'failed';

// Visibilité (ADR-061) : publique, ou privée (« Toi uniquement »), visible de son seul auteur.
export type VideoVisibility = 'public' | 'private';
export const VIDEO_VISIBILITIES: VideoVisibility[] = ['public', 'private'];

export interface Video {
  id: string;
  userId: string;
  description: string | null;
  // Clé de l'objet brut dans le bucket des uploads.
  rawKey: string;
  // Upload multipart en cours ; nul une fois l'upload terminé.
  uploadId: string | null;
  // Taille déclarée du fichier brut, en octets.
  rawSize: number;
  status: VideoStatus;
  visibility: VideoVisibility;
  // Commentaires autorisés (ADR-062) : coupés, ils sont cachés à tous sauf à l'auteur.
  commentsEnabled: boolean;
  // « Autoriser l'utilisation de mon son » (ADR-064).
  soundShared: boolean;
  hlsUrl: string | null;
  thumbnailUrl: string | null;
  // Son repris d'une autre vidéo (ADR-064), nul sinon ou s'il a disparu.
  soundId: string | null;
  // Couverture choisie dans l'app (ADR-065), dans le bucket des uploads ; jamais exposée.
  coverKey: string | null;
  // Étiquette « Contenu généré par l'IA » et lieu (nom, adresse affichée ; jamais de coordonnées), ADR-065.
  aiGenerated: boolean;
  locationName: string | null;
  locationAddress: string | null;
  createdAt: Date;
}

// Vidéo publiée (`ready`), telle que diffusée dans le feed : lecture HLS et compteurs dénormalisés (ADR-006).
export interface PublishedVideo {
  id: string;
  userId: string;
  description: string | null;
  visibility: VideoVisibility;
  // Commentaires autorisés (ADR-062) : coupés, ils sont cachés à tous sauf à l'auteur.
  commentsEnabled: boolean;
  // « Autoriser l'utilisation de mon son » (ADR-064).
  soundShared: boolean;
  // Étiquette « Contenu généré par l'IA » et lieu (nom, adresse affichée ; jamais de coordonnées), ADR-065.
  aiGenerated: boolean;
  locationName: string | null;
  locationAddress: string | null;
  hlsUrl: string;
  thumbnailUrl: string;
  viewsCount: number;
  likesCount: number;
  commentsCount: number;
  favoritesCount: number;
  sharesCount: number;
  repostsCount: number;
  createdAt: Date;
}

// Vidéo vue par le backoffice (ADR-004) : quel que soit son statut, avec ses compteurs.
export interface VideoDetails {
  id: string;
  userId: string;
  description: string | null;
  status: VideoStatus;
  visibility: VideoVisibility;
  // Commentaires autorisés (ADR-062) : coupés, ils sont cachés à tous sauf à l'auteur.
  commentsEnabled: boolean;
  // « Autoriser l'utilisation de mon son » (ADR-064).
  soundShared: boolean;
  // Étiquette « Contenu généré par l'IA » et lieu (nom, adresse affichée ; jamais de coordonnées), ADR-065.
  aiGenerated: boolean;
  locationName: string | null;
  locationAddress: string | null;
  hlsUrl: string | null;
  thumbnailUrl: string | null;
  viewsCount: number;
  likesCount: number;
  commentsCount: number;
  favoritesCount: number;
  sharesCount: number;
  repostsCount: number;
  createdAt: Date;
}

// Filtres de la liste des vidéos du backoffice.
export interface VideoFilter {
  status?: VideoStatus;
  userId?: string;
}

// Vidéos non publiées (en traitement ou en échec) montrées à leur auteur : les plus récentes seulement.
// Il n'y a pas encore de suppression de vidéo : les échecs s'accumulent.
export const MAX_UNPUBLISHED_VIDEOS = 50;

// Position dans une liste de vidéos triée de la plus récente à la plus ancienne (date, puis identifiant).
export interface VideoPosition {
  createdAt: Date;
  id: string;
}

// Résultat du transcodage renvoyé par le worker (ADR-008, ADR-012).
// `sound` : piste son extraite (ADR-064), pour une vidéo qui a du son.
export type TranscodeOutcome =
  { status: 'ready'; hlsUrl: string; thumbnailUrl: string; sound?: { audioUrl: string; durationMs: number } } | { status: 'failed' };

export interface NewVideo {
  userId: string;
  description: string | null;
  rawKey: string;
  uploadId: string;
  rawSize: number;
  // Publique par défaut (ADR-061).
  visibility?: VideoVisibility;
  // Autorisés par défaut (ADR-062).
  commentsEnabled?: boolean;
  // Autorisé par défaut (ADR-064).
  soundShared?: boolean;
  // Son repris d'une autre vidéo (ADR-064).
  soundId?: string | null;
  // ADR-065 : couverture envoyée par l'app, étiquette IA (faux par défaut), lieu.
  coverKey?: string | null;
  aiGenerated?: boolean;
  locationName?: string | null;
  locationAddress?: string | null;
}

// Lieu de la publication (ADR-065), longueurs bornées (aussi par une contrainte CHECK).
export const MAX_LOCATION_NAME_LENGTH = 100;
export const MAX_LOCATION_ADDRESS_LENGTH = 200;

// Son d'une vidéo publiée, réutilisable par les autres (ADR-064) : « Son original - @pseudo ».
export interface Sound {
  id: string;
  // Vidéo d'où vient le son, et son auteur.
  videoId: string;
  userId: string;
  audioUrl: string;
  durationMs: number;
  // Miniature de la vidéo d'origine.
  coverUrl: string;
  // Vidéos publiques publiées qui l'utilisent.
  usesCount: number;
  createdAt: Date;
}

// Sons proposés (ADR-064) : seulement ceux d'une vidéo publique, publiée, qui le permet, dont l'auteur n'est pas masqué.
export type SoundQuery =
  // Les plus utilisés, puis les plus récents.
  | { kind: 'recommended' }
  // Description de la vidéo contenant le texte (sans casse), ou auteur parmi `authorIds`.
  | { kind: 'search'; text: string; authorIds: string[] }
  // Favoris d'un compte, du plus récemment ajouté au plus ancien.
  | { kind: 'favorites'; userId: string }
  // Sons demandés (« Récents » de l'app), dans un ordre quelconque.
  | { kind: 'ids'; ids: string[] };

// Nombre de sons d'une page, et nombre de sons lisibles en tout dans une liste (comme la recherche de comptes).
export const SOUND_PAGE_SIZE = 20;
export const MAX_SOUND_PAGE_SIZE = 50;
export const MAX_SOUND_RESULTS = 200;
export const MAX_SOUND_IDS = 50;
