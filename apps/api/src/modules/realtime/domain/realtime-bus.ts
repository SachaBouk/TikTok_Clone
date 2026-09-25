import type { RealtimeMessage } from './realtime';

// Diffusion entre les instances de l'API (ADR-011 : Redis pub/sub). Chaque instance reçoit tous
// les messages, y compris les siens, et les remet aux connexions qu'elle détient.
export abstract class RealtimeBus {
  // Au mieux : un échec de diffusion est journalisé, jamais propagé. Le temps réel n'est qu'un raccourci,
  // l'API REST reste la source de vérité.
  abstract publish(message: RealtimeMessage): Promise<void>;
  // Renvoie la fonction qui arrête l'écoute.
  abstract subscribe(handler: (message: RealtimeMessage) => void): Promise<() => Promise<void>>;
}
