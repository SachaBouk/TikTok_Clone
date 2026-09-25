import type { Video } from './video';

// Événements du module vers l'app de l'auteur (ADR-008 : fin du traitement notifiée par WebSocket, ADR-011).
// Au mieux : l'app ne les reçoit que si elle est connectée, et relit sinon `GET /videos/:id`.
export abstract class VideoEventPublisher {
  // Transcodage terminé : vidéo `ready` ou `failed`.
  abstract videoProcessed(video: Video): Promise<void>;
}
