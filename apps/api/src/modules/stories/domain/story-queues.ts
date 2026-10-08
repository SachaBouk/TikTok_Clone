import type { StoryFiles } from './story';

// File de transcodage des stories vidéo (BullMQ `story-transcode`, consommée par apps/worker, ADR-012, ADR-051).
export abstract class StoryTranscodingQueue {
  abstract enqueue(job: { storyId: string; rawKey: string }): Promise<void>;
  // Retire le job d'une story supprimée s'il attend encore ; sans effet s'il est en cours.
  abstract cancel(storyId: string): Promise<void>;
}

// Nettoyage programmé AVANT la suppression en base, avec ce délai : si la suppression échoue, l'exécution trouve la story
// encore en base et ne touche à rien (même principe que les vidéos).
export const STORY_CLEANUP_DELAY_MS = 30_000;

// Expiration et nettoyage des fichiers (BullMQ `story-expiry` et `story-cleanup`, produites et consommées par l'API).
export abstract class StoryLifecycleQueue {
  // Job différé qui supprime la story à son échéance (`jobId` = identifiant de la story : programmé une seule fois). Une
  // story supprimée avant garde son job, qui ne trouvera rien.
  abstract scheduleExpiry(storyId: string, at: Date): Promise<void>;
  // Erreur propagée : la suppression ne doit pas avoir lieu si le nettoyage n'a pas pu être programmé.
  abstract scheduleCleanup(files: StoryFiles[], delayMs: number): Promise<void>;
}
