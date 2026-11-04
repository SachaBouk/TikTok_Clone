// Cycle de vie (ADR-008) : uploading → processing → ready / failed.
export type VideoStatus = 'uploading' | 'processing' | 'ready' | 'failed';

// Visibilité (ADR-061) : publique, ou privée (« Toi uniquement »), visible de son seul auteur.
export type VideoVisibility = 'public' | 'private';
export const VIDEO_VISIBILITIES: VideoVisibility[] = ['public', 'private'];

// Hébergeur (ADR-074) : pipeline maison (MinIO, worker FFmpeg) ou Mux, retenu à l'envoi et gardé par la vidéo.
export type VideoProvider = 'local' | 'mux';

// Lecture d'une vidéo Mux : identifiant de lecture, signé (jeton dans les URLs) pour une vidéo privée (ADR-061). Les URLs
// gardées en base sont celles sans jeton ; le service y ajoute le jeton à chaque lecture.
export interface MuxPlayback {
  muxPlaybackId?: string | null;
  muxSigned?: boolean;
}

export interface Video {
  id: string;
  userId: string;
  description: string | null;
  // Clé de l'objet brut dans le bucket des uploads. Vidéo Mux (ADR-074) : jamais écrite, elle situe la couverture.
  rawKey: string;
  // Upload multipart en cours ; nul une fois l'upload terminé (toujours nul pour une vidéo Mux).
  uploadId: string | null;
  provider: VideoProvider;
  // Mux (ADR-074) : envoi direct, puis asset et identifiant de lecture (signé pour une vidéo privée). Jamais exposés.
  muxUploadId: string | null;
  muxAssetId: string | null;
  muxPlaybackId: string | null;
  muxSigned: boolean;
  // Taille déclarée du fichier brut, en octets.
  rawSize: number;
  status: VideoStatus;
  visibility: VideoVisibility;
  // Commentaires autorisés (ADR-062) : coupés, ils sont cachés à tous sauf à l'auteur.
  commentsEnabled: boolean;
  // « Autoriser l'utilisation de mon son » (ADR-064).
  soundShared: boolean;
  // « Autoriser le téléchargement » (ADR-067) : refusé, seul l'auteur télécharge la vidéo.
  downloadsEnabled: boolean;
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
  // Durée maximale permise (ADR-073) : fixée à la confirmation de l'envoi, 600 s pour un abonné « Plus » ; nulle sinon
  // (durée par défaut du worker, ADR-040).
  maxDurationSeconds: number | null;
  createdAt: Date;
}

// Vidéo publiée (`ready`), telle que diffusée dans le feed : lecture HLS et compteurs dénormalisés (ADR-006).
export interface PublishedVideo extends MuxPlayback {
  id: string;
  userId: string;
  description: string | null;
  visibility: VideoVisibility;
  // Commentaires autorisés (ADR-062) : coupés, ils sont cachés à tous sauf à l'auteur.
  commentsEnabled: boolean;
  // « Autoriser l'utilisation de mon son » (ADR-064).
  soundShared: boolean;
  // « Autoriser le téléchargement » (ADR-067) : refusé, seul l'auteur télécharge la vidéo.
  downloadsEnabled: boolean;
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
export interface VideoDetails extends MuxPlayback {
  id: string;
  userId: string;
  description: string | null;
  status: VideoStatus;
  visibility: VideoVisibility;
  // Commentaires autorisés (ADR-062) : coupés, ils sont cachés à tous sauf à l'auteur.
  commentsEnabled: boolean;
  // « Autoriser l'utilisation de mon son » (ADR-064).
  soundShared: boolean;
  // « Autoriser le téléchargement » (ADR-067) : refusé, seul l'auteur télécharge la vidéo.
  downloadsEnabled: boolean;
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

// Compte qui publie (ADR-068) : nombre de vidéos publiées et publiques.
export interface PublishingAuthor {
  userId: string;
  videosCount: number;
}

// Résultat du transcodage renvoyé par le worker (ADR-008, ADR-012).
// `sound` : piste son extraite (ADR-064), pour une vidéo qui a du son.
export type TranscodeOutcome =
  { status: 'ready'; hlsUrl: string; thumbnailUrl: string; sound?: { audioUrl: string; durationMs: number } } | { status: 'failed' };

export interface NewVideo {
  // Choisi par le service pour une vidéo Mux (`passthrough`, ADR-074) ; sinon généré par la base.
  id?: string;
  userId: string;
  description: string | null;
  rawKey: string;
  // Upload multipart S3 (pipeline maison) ; nul pour une vidéo Mux.
  uploadId: string | null;
  rawSize: number;
  // Pipeline maison par défaut ; Mux : identifiant de l'envoi direct, identifiant de lecture signé ou non.
  provider?: VideoProvider;
  muxUploadId?: string | null;
  muxSigned?: boolean;
  // Publique par défaut (ADR-061).
  visibility?: VideoVisibility;
  // Autorisés par défaut (ADR-062).
  commentsEnabled?: boolean;
  // Autorisé par défaut (ADR-064).
  soundShared?: boolean;
  // « Autoriser le téléchargement » (ADR-067).
  downloadsEnabled?: boolean;
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
