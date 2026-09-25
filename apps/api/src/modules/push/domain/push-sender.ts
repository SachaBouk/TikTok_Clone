import type { PushDevice, PushMessage, PushResult } from './push';

// Envoi à un appareil (APNs). Lève une erreur pour un échec temporaire (réseau, APNs indisponible) : l'envoi est relancé.
export abstract class PushSender {
  abstract send(device: PushDevice, message: PushMessage): Promise<PushResult>;
}
