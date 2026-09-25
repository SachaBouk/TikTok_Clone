import type { PushDevice, PushEnvironment, PushMessage, PushResult } from '../domain/push';
import type { PushDeviceRepository } from '../domain/push-device.repository';
import type { PushQueue } from '../domain/push-queue';
import type { PushSender } from '../domain/push-sender';

// Service applicatif des notifications push (ADR-003). Exporté : les modules videos, notifications et
// messaging lui confient leurs messages ; il les met en file, un envoi par appareil du compte.
export class PushService {
  constructor(
    private readonly devices: PushDeviceRepository,
    private readonly queue: PushQueue,
    private readonly sender: PushSender,
  ) {}

  // Au lancement de l'app (et à chaque changement de token) ; idempotent.
  registerDevice(userId: string, token: string, environment: PushEnvironment): Promise<void> {
    return this.devices.register({ userId, token, environment });
  }

  // À la déconnexion : l'appareil ne reçoit plus les notifications de ce compte.
  unregisterDevice(userId: string, token: string): Promise<void> {
    return this.devices.unregister(userId, token);
  }

  async notify(userId: string, message: PushMessage): Promise<void> {
    for (const device of await this.devices.findByUser(userId)) await this.queue.enqueue({ device, message });
  }

  // Appelé par la file. Un token refusé par APNs est oublié. Un échec temporaire lève une erreur (relance).
  async deliver(device: PushDevice, message: PushMessage): Promise<PushResult> {
    const result = await this.sender.send(device, message);
    if (result === 'invalidToken') await this.devices.remove(device.token);
    return result;
  }
}
