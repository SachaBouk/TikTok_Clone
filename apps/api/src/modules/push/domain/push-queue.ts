import type { PushDevice, PushMessage } from './push';

// File d'envoi (ADR-012 : BullMQ) : l'envoi à APNs ne ralentit pas la requête, et il est relancé en cas d'échec.
export abstract class PushQueue {
  // Au mieux : un échec de mise en file est journalisé, jamais propagé.
  abstract enqueue(delivery: { device: PushDevice; message: PushMessage }): Promise<void>;
}
