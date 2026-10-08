import { InvalidMediaError, type MediaInfo } from './ffmpeg';

// Durée maximale d'une vidéo publiée (ADR-040, choix du développeur : format court). L'app refuse déjà une vidéo plus
// longue avant l'envoi ; le worker revérifie (client modifié, script) avant de transcoder, sans consommer de calcul.
export const MAX_VIDEO_DURATION_SECONDS = 180;
// Durée maximale d'une story vidéo (ADR-051), même principe.
export const MAX_STORY_DURATION_SECONDS = 60;
// Marge pour les arrondis du conteneur : une vidéo affichée « 3:00 » dure souvent un peu plus de 180 s.
export const DURATION_TOLERANCE_SECONDS = 1;

// Vidéo trop longue : `InvalidMediaError`, donc échec définitif immédiat, sans relance (comme un fichier illisible).
export function assertPublishable(media: Pick<MediaInfo, 'durationSeconds'>, maxSeconds: number = MAX_VIDEO_DURATION_SECONDS): void {
  if (media.durationSeconds > maxSeconds + DURATION_TOLERANCE_SECONDS) {
    throw new InvalidMediaError(`vidéo trop longue (${Math.round(media.durationSeconds)} s, ${maxSeconds} s au plus)`);
  }
}
