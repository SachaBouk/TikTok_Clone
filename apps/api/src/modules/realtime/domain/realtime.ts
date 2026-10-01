import type { RealtimeEventDto } from '@repo/shared';

// Temps réel (ADR-011) : un WebSocket par appareil connecté, authentifié au handshake par l'access token.
// Le serveur pousse des événements à un compte. L'app envoie peu de choses (`typing`) : les modules
// enregistrent leurs gestionnaires auprès de RealtimeService ; les autres messages sont ignorés.

// Compte identifié au handshake, jusqu'à l'expiration de son access token.
export interface RealtimeSession {
  userId: string;
  expiresAt: Date;
}

// Une connexion ouverte, vue du service : indépendante de la bibliothèque WebSocket.
export interface RealtimeConnection {
  send(message: string): void;
  close(code: number, reason: string): void;
}

// Message du bus, adressé à tous les appareils connectés d'un compte, sur toutes les instances de l'API : un
// événement, ou la fermeture de ses connexions (compte suspendu, ADR-037).
export type RealtimeMessage = { userId: string; event: RealtimeEventDto } | { userId: string; disconnect: true };

// Chemin du WebSocket, sur le port de l'API : ws://<hôte>:3000/realtime.
export const REALTIME_PATH = '/realtime';

// Codes de fermeture (4000-4999 : réservés aux applications).
// Access token expiré : l'app rafraîchit sa paire de tokens (POST /auth/refresh) et se reconnecte.
// Aussi pour un compte suspendu (ADR-037) : le rafraîchissement échoue alors, et l'app repasse en invité.
export const CLOSE_SESSION_EXPIRED = 4001;
// Arrêt ou redémarrage de l'instance (code standard « going away ») : l'app se reconnecte.
export const CLOSE_GOING_AWAY = 1001;

// Détection des connexions mortes côté serveur : un ping par intervalle, et la connexion est coupée
// si le pong du ping précédent n'est pas arrivé. L'app fait de même de son côté (ADR-011).
export const HEARTBEAT_INTERVAL_MS = 30_000;

// Taille maximale d'un message de l'app (au-delà, `ws` ferme la connexion avec le code 1009).
export const MAX_CLIENT_MESSAGE_BYTES = 4096;

// Gestionnaire d'un message de l'app, par type (`event`). `data` n'est pas validé : au gestionnaire de le faire.
export type ClientMessageHandler = (userId: string, data: unknown) => Promise<void>;
