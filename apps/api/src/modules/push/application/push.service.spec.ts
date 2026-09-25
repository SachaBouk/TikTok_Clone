import { beforeEach, describe, expect, it } from 'vitest';
import { InMemoryPushDeviceRepository, InMemoryPushQueue, InMemoryPushSender } from '../infrastructure/in-memory-push';
import { PushService } from './push.service';

const TOKEN_A = 'a'.repeat(64);
const TOKEN_B = 'b'.repeat(64);
const message = { title: 'Léa', body: 'Salut', threadId: 'conversation:1', data: { type: 'message' } };

describe('PushService', () => {
  let devices: InMemoryPushDeviceRepository;
  let queue: InMemoryPushQueue;
  let sender: InMemoryPushSender;
  let service: PushService;

  beforeEach(() => {
    devices = new InMemoryPushDeviceRepository();
    queue = new InMemoryPushQueue();
    sender = new InMemoryPushSender();
    service = new PushService(devices, queue, sender);
  });

  it('met en file un envoi par appareil du compte', async () => {
    await service.registerDevice('alice', TOKEN_A, 'production');
    await service.registerDevice('alice', TOKEN_B, 'sandbox');
    await service.notify('alice', message);
    await service.notify('bob', message);
    expect(queue.deliveries.map((d) => [d.device.token, d.device.environment])).toEqual([
      [TOKEN_A, 'production'],
      [TOKEN_B, 'sandbox'],
    ]);
  });

  it('un token passe au dernier compte connecté ; on ne retire que le sien', async () => {
    await service.registerDevice('alice', TOKEN_A, 'production');
    await service.registerDevice('bob', TOKEN_A, 'production');
    await service.unregisterDevice('alice', TOKEN_A);
    expect([...devices.devices.values()]).toEqual([{ token: TOKEN_A, userId: 'bob', environment: 'production' }]);
    await service.unregisterDevice('bob', TOKEN_A);
    expect(devices.devices.size).toBe(0);
  });

  it('oublie un appareil dont APNs refuse le token', async () => {
    await service.registerDevice('alice', TOKEN_A, 'production');
    const device = (await devices.findByUser('alice'))[0]!;
    await expect(service.deliver(device, message)).resolves.toBe('sent');
    sender.invalidTokens.add(TOKEN_A);
    await expect(service.deliver(device, message)).resolves.toBe('invalidToken');
    expect(devices.devices.size).toBe(0);
  });
});
