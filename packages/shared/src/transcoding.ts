// Contrat des files BullMQ entre apps/api et apps/worker (ADR-012).
// L'API publie les jobs de transcodage ; le worker publie les résultats, que l'API applique en base :
// seule l'API écrit dans PostgreSQL (ADR-003).

export const TRANSCODE_QUEUE = 'video-transcode';
export const TRANSCODE_RESULTS_QUEUE = 'video-transcode-results';

// Politique de relance, fixée par l'API à la publication : 3 tentatives, espacées de 10 s puis 20 s.
export const TRANSCODE_ATTEMPTS = 3;
export const TRANSCODE_BACKOFF_DELAY_MS = 10_000;

export interface TranscodeJobData {
  videoId: string;
  // Clé de l'objet brut dans le bucket des uploads.
  rawKey: string;
}

export type TranscodeResult =
  | { videoId: string; status: 'ready'; hlsUrl: string; thumbnailUrl: string }
  // Publié après la dernière tentative en échec.
  | { videoId: string; status: 'failed'; reason: string };
