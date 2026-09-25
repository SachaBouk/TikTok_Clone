import type { RealtimeEventDto } from '@repo/shared';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { AccessTokenVerifier } from '../domain/access-token-verifier';
import { CLOSE_GOING_AWAY, CLOSE_SESSION_EXPIRED, type RealtimeConnection, type RealtimeSession } from '../domain/realtime';
import { InMemoryRealtimeBus } from '../infrastructure/in-memory-realtime-bus';
import { RealtimeService } from './realtime.service';

class FakeVerifier extends AccessTokenVerifier {
  constructor(private readonly sessions: Record<string, RealtimeSession>) {
    super();
  }

  async verify(token: string) {
    return this.sessions[token] ?? null;
  }
}

class FakeConnection implements RealtimeConnection {
  readonly received: RealtimeEventDto[] = [];
  closed: { code: number; reason: string } | null = null;

  send(message: string) {
    this.received.push(JSON.parse(message) as RealtimeEventDto);
  }

  close(code: number, reason: string) {
    this.closed = { code, reason };
  }
}

const NOW = new Date('2026-09-25T10:00:00.000Z');
const in15min = new Date(NOW.getTime() + 15 * 60_000);
const badge = (unreadCount: number): RealtimeEventDto => ({ event: 'unreadNotificationsChanged', data: { unreadCount } });

describe('RealtimeService', () => {
  let bus: InMemoryRealtimeBus;
  let service: RealtimeService;

  beforeEach(async () => {
    vi.useFakeTimers({ now: NOW });
    bus = new InMemoryRealtimeBus();
    service = new RealtimeService(bus, new FakeVerifier({ valide: { userId: 'alice', expiresAt: in15min } }));
    await service.start();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("authentifie le handshake par l'access token", async () => {
    await expect(service.authenticate('valide')).resolves.toEqual({ userId: 'alice', expiresAt: in15min });
    await expect(service.authenticate('invalide')).resolves.toBeNull();
    await expect(service.authenticate(null)).resolves.toBeNull();
  });

  it('remet un événement à tous les appareils du compte, et seulement à eux', async () => {
    const phone = new FakeConnection();
    const tablet = new FakeConnection();
    const other = new FakeConnection();
    service.attach(phone, { userId: 'alice', expiresAt: in15min });
    service.attach(tablet, { userId: 'alice', expiresAt: in15min });
    service.attach(other, { userId: 'bob', expiresAt: in15min });

    await service.sendToUser('alice', badge(3));

    expect(phone.received).toEqual([badge(3)]);
    expect(tablet.received).toEqual([badge(3)]);
    expect(other.received).toEqual([]);
    expect(bus.published).toEqual([{ userId: 'alice', event: badge(3) }]);
  });

  it('ne remet plus rien à une connexion fermée', async () => {
    const phone = new FakeConnection();
    const detach = service.attach(phone, { userId: 'alice', expiresAt: in15min });
    detach();
    await service.sendToUser('alice', badge(1));
    expect(phone.received).toEqual([]);
    expect(service.connectionCount).toBe(0);
  });

  it("ferme la connexion à l'expiration de l'access token (4001)", async () => {
    const phone = new FakeConnection();
    service.attach(phone, { userId: 'alice', expiresAt: in15min });

    vi.advanceTimersByTime(15 * 60_000 - 1);
    expect(phone.closed).toBeNull();
    vi.advanceTimersByTime(1);
    expect(phone.closed?.code).toBe(CLOSE_SESSION_EXPIRED);
  });

  it("ferme tout de suite une session déjà expirée, sans l'enregistrer", () => {
    const late = new FakeConnection();
    service.attach(late, { userId: 'alice', expiresAt: NOW });
    expect(late.closed?.code).toBe(CLOSE_SESSION_EXPIRED);
    expect(service.connectionCount).toBe(0);
  });

  it("n'expire pas une connexion déjà fermée", () => {
    const phone = new FakeConnection();
    service.attach(phone, { userId: 'alice', expiresAt: in15min })();
    vi.advanceTimersByTime(15 * 60_000);
    expect(phone.closed).toBeNull();
  });

  it("remet les messages de l'app au gestionnaire de leur type, ignore le reste", async () => {
    const received: [string, unknown][] = [];
    service.onClientMessage('typing', async (userId, data) => {
      received.push([userId, data]);
    });
    await service.receive('alice', JSON.stringify({ event: 'typing', data: { conversationId: 'c1' } }));
    for (const garbage of ['pas du json', '42', 'null', '{"event":"inconnu"}', '{"data":1}']) await service.receive('alice', garbage);
    expect(received).toEqual([['alice', { conversationId: 'c1' }]]);
  });

  it("à l'arrêt, ferme les connexions (1001) et cesse d'écouter le bus", async () => {
    const phone = new FakeConnection();
    service.attach(phone, { userId: 'alice', expiresAt: in15min });
    await service.stop();

    expect(phone.closed?.code).toBe(CLOSE_GOING_AWAY);
    await service.sendToUser('alice', badge(1));
    expect(phone.received).toEqual([]);
  });
});
