import type { PushDevice, PushMessage, PushResult } from '../domain/push';
import { PushDeviceRepository } from '../domain/push-device.repository';
import { PushQueue } from '../domain/push-queue';
import { PushSender } from '../domain/push-sender';

// Adaptateurs en mémoire pour les tests.

export class InMemoryPushDeviceRepository extends PushDeviceRepository {
  readonly devices = new Map<string, PushDevice>();

  async register(device: PushDevice): Promise<void> {
    this.devices.set(device.token, { ...device });
  }

  async unregister(userId: string, token: string): Promise<void> {
    if (this.devices.get(token)?.userId === userId) this.devices.delete(token);
  }

  async findByUser(userId: string): Promise<PushDevice[]> {
    return [...this.devices.values()].filter((d) => d.userId === userId);
  }

  async remove(token: string): Promise<void> {
    this.devices.delete(token);
  }
}

export class InMemoryPushQueue extends PushQueue {
  readonly deliveries: { device: PushDevice; message: PushMessage }[] = [];

  async enqueue(delivery: { device: PushDevice; message: PushMessage }): Promise<void> {
    this.deliveries.push(delivery);
  }
}

export class InMemoryPushSender extends PushSender {
  readonly sent: { device: PushDevice; message: PushMessage }[] = [];
  readonly invalidTokens = new Set<string>();

  async send(device: PushDevice, message: PushMessage): Promise<PushResult> {
    if (this.invalidTokens.has(device.token)) return 'invalidToken';
    this.sent.push({ device, message });
    return 'sent';
  }
}
