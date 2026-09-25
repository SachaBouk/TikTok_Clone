export interface TranscodingJob {
  videoId: string;
  rawKey: string;
}

// File de transcodage (ADR-012 : BullMQ, queue `video-transcode`), consommée par apps/worker (ADR-008).
export abstract class TranscodingQueue {
  abstract enqueue(job: TranscodingJob): Promise<void>;
  // Retire le job d'une vidéo supprimée s'il attend encore. Sans effet s'il est en cours : le worker
  // ira au bout, et son résultat, sans vidéo en base, déclenchera le nettoyage des fichiers produits.
  abstract cancel(videoId: string): Promise<void>;
}
