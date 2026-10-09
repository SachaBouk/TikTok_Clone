import type { User } from '../../users/domain/user';
import type { GiftDetails } from './live-events';
import type { LiveEndReason, LiveMessage } from './live';

// Port du serveur vidéo (ADR-053, LiveKit) : une salle par live (nom = identifiant du live), jetons d'accès signés, et
// événements de la salle. Le domaine ne connaît ni LiveKit ni son SDK.
export abstract class LiveMedia {
  // Adresse du serveur donnée à l'app (WebSocket).
  abstract readonly publicUrl: string;
  abstract createRoom(liveId: string): Promise<void>;
  // Sans erreur si la salle n'existe plus. Déconnecte tout le monde.
  abstract deleteRoom(liveId: string): Promise<void>;
  // Salles ouvertes sur le serveur (maintenance).
  abstract listRooms(): Promise<string[]>;
  abstract isConnected(liveId: string, identity: string): Promise<boolean>;
  // Jeton d'accès à la salle : publier (l'auteur) ou seulement regarder.
  abstract createToken(grant: { liveId: string; identity: string; name: string; canPublish: boolean; ttlSeconds: number }): Promise<string>;
  // Webhook du serveur : corps brut et en-tête Authorization. Erreur si la signature ne correspond pas ; null pour un
  // événement sans intérêt pour le live.
  abstract receiveWebhook(body: string, authorization: string | undefined): Promise<LiveMediaEvent | null>;
}

// Événement du serveur vidéo (webhook), déjà vérifié par l'adaptateur.
export type LiveMediaEvent =
  | { type: 'participantJoined'; liveId: string; identity: string; participantsCount: number }
  | { type: 'participantLeft'; liveId: string; identity: string }
  | { type: 'roomFinished'; liveId: string };

// Port des événements diffusés dans la salle (chat, cœurs, cadeaux, fin), reçus par tous ses participants, invités compris.
export abstract class LiveRoomPublisher {
  abstract chatMessage(message: LiveMessage, author: User): Promise<void>;
  abstract chatMessageDeleted(liveId: string, messageId: string): Promise<void>;
  abstract hearts(liveId: string, count: number, total: number): Promise<void>;
  abstract gift(liveId: string, sender: User, gift: GiftDetails, totals: { giftsCount: number; giftsAmount: number }): Promise<void>;
  abstract liveEnded(liveId: string, reason: LiveEndReason): Promise<void>;
}

// Jobs différés du live (BullMQ, produits et consommés par l'API).
export abstract class LiveLifecycleQueue {
  // Fin à la durée maximale (`jobId` = live : programmé une seule fois).
  abstract scheduleTimeLimit(liveId: string, at: Date): Promise<void>;
  // Vérifie, après ce délai, que l'auteur est connecté à la salle ; remplace une vérification déjà programmée.
  abstract scheduleHostCheck(liveId: string, delayMs: number): Promise<void>;
}
