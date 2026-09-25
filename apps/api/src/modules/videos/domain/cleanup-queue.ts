// Nettoyage des fichiers d'une vidéo supprimée : brut (et upload multipart en cours) dans le bucket des
// uploads, HLS et miniature sous `<videoId>/` dans le bucket HLS.
export interface VideoFilesCleanup {
  videoId: string;
  // Absent quand seuls les fichiers HLS restent à supprimer (résultat de transcodage arrivé après la suppression).
  rawKey: string | null;
  uploadId: string | null;
}

// Programmé AVANT de supprimer la vidéo en base, avec ce délai : si la suppression échoue, l'exécution
// trouve la vidéo encore en base et ne touche à rien. Si la programmation échoue, rien n'est supprimé.
export const CLEANUP_DELAY_MS = 30_000;

// Port de la file de nettoyage (BullMQ `video-cleanup`, produite et consommée par l'API, ADR-012) :
// relances en cas d'échec du stockage, sans ralentir la requête de suppression.
export abstract class VideoCleanupQueue {
  abstract schedule(cleanups: VideoFilesCleanup[], delayMs: number): Promise<void>;
}
