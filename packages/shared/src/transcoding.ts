// Contrat des files BullMQ entre apps/api et apps/worker (ADR-012).
// L'API publie les jobs de transcodage ; le worker publie les résultats, que l'API applique en base :
// seule l'API écrit dans PostgreSQL (ADR-003).

export const TRANSCODE_QUEUE = 'video-transcode';
export const TRANSCODE_RESULTS_QUEUE = 'video-transcode-results';
// Stories vidéo (ADR-051) : mêmes messages et même traitement, dans leurs propres files (60 s au plus au lieu de 3 min).
// `videoId` y désigne la story : son préfixe dans le bucket HLS.
export const STORY_TRANSCODE_QUEUE = 'story-transcode';
export const STORY_TRANSCODE_RESULTS_QUEUE = 'story-transcode-results';

// Politique de relance, fixée par l'API à la publication : 3 tentatives, espacées de 10 s puis 20 s.
export const TRANSCODE_ATTEMPTS = 3;
export const TRANSCODE_BACKOFF_DELAY_MS = 10_000;

export interface TranscodeJobData {
  // Vidéo, ou story dans les files des stories.
  videoId: string;
  // Clé de l'objet brut dans le bucket des uploads.
  rawKey: string;
  // Couverture choisie dans l'app (ADR-065), JPEG dans le bucket des uploads : elle devient la miniature. Absente ou
  // illisible, la miniature est prise dans la vidéo.
  coverKey?: string;
}

export type TranscodeResult =
  // `soundUrl` / `soundDurationSeconds` : piste son extraite en AAC (ADR-064), seulement pour une vidéo (pas une
  // story) qui a du son.
  | { videoId: string; status: 'ready'; hlsUrl: string; thumbnailUrl: string; soundUrl?: string; soundDurationSeconds?: number }
  // Publié après la dernière tentative en échec.
  | { videoId: string; status: 'failed'; reason: string };
