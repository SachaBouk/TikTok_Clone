import { InMemoryRateLimiter } from '../../../rate-limit/in-memory-rate-limiter';
import type { InteractionsService } from '../../interactions/application/interactions.service';
import type { NotificationsService } from '../../notifications/application/notifications.service';
import type { UsersService } from '../../users/application/users.service';
import type { User } from '../../users/domain/user';
import { LiveService } from '../application/live.service';
import type { Live, LiveEndReason, LiveMessage } from '../domain/live';
import type { GiftDetails } from '../domain/live-events';
import { LiveLifecycleQueue, LiveMedia, type LiveMediaEvent, LiveRoomPublisher } from '../domain/live-media';
import { LiveRepository, type NewLive, type NewLiveMessage } from '../domain/live.repository';

// Adaptateurs en mémoire du live (ADR-053), pour les tests du service et des modules qui en dépendent (wallet, messaging,
// reports, admin). Reproduisent l'index unique « un live en cours par compte » et la fin atomique.

export class InMemoryLiveRepository extends LiveRepository {
  readonly lives = new Map<string, Live>();
  readonly viewers = new Map<string, Set<string>>();
  readonly messages: LiveMessage[] = [];
  private sequence = 0;

  async create(input: NewLive): Promise<Live | null> {
    if ([...this.lives.values()].some((live) => live.userId === input.userId && live.status === 'live')) return null;
    const live: Live = {
      ...input,
      status: 'live',
      endedAt: null,
      endReason: null,
      peakViewers: 0,
      heartsCount: 0,
      giftsCount: 0,
      giftsAmount: 0,
    };
    this.lives.set(live.id, live);
    return { ...live };
  }

  async findById(id: string): Promise<Live | null> {
    const live = this.lives.get(id);
    return live ? { ...live } : null;
  }

  async findByIds(ids: string[]): Promise<Live[]> {
    return ids.flatMap((id) => (this.lives.has(id) ? [{ ...this.lives.get(id)! }] : []));
  }

  async findInProgressByUser(userId: string): Promise<Live | null> {
    const live = [...this.lives.values()].find((l) => l.userId === userId && l.status === 'live');
    return live ? { ...live } : null;
  }

  async findInProgressByUsers(userIds: string[]): Promise<Live[]> {
    return [...this.lives.values()]
      .filter((live) => live.status === 'live' && userIds.includes(live.userId))
      .sort((a, b) => b.startedAt.getTime() - a.startedAt.getTime())
      .map((live) => ({ ...live }));
  }

  async end(id: string, reason: LiveEndReason, at: Date): Promise<Live | null> {
    const live = this.lives.get(id);
    if (!live || live.status !== 'live') return null;
    Object.assign(live, { status: 'ended', endedAt: at, endReason: reason });
    return { ...live };
  }

  async recordViewer(liveId: string, identity: string): Promise<void> {
    const set = this.viewers.get(liveId) ?? new Set<string>();
    set.add(identity);
    this.viewers.set(liveId, set);
  }

  async raisePeakViewers(liveId: string, count: number): Promise<void> {
    const live = this.lives.get(liveId);
    if (live && live.peakViewers < count) live.peakViewers = count;
  }

  async countViewers(liveId: string, excludedIdentity: string): Promise<number> {
    return [...(this.viewers.get(liveId) ?? [])].filter((identity) => identity !== excludedIdentity).length;
  }

  async addHearts(liveId: string, count: number): Promise<number> {
    const live = this.lives.get(liveId)!;
    live.heartsCount += count;
    return live.heartsCount;
  }

  async addGift(liveId: string, amount: number): Promise<{ giftsCount: number; giftsAmount: number }> {
    const live = this.lives.get(liveId)!;
    live.giftsCount += 1;
    live.giftsAmount += amount;
    return { giftsCount: live.giftsCount, giftsAmount: live.giftsAmount };
  }

  async addMessage(input: NewLiveMessage): Promise<LiveMessage> {
    const message = { id: `00000000-0000-7000-9000-${String(++this.sequence).padStart(12, '0')}`, ...input };
    this.messages.push(message);
    return { ...message };
  }

  async findMessage(id: string): Promise<LiveMessage | null> {
    return this.messages.find((message) => message.id === id) ?? null;
  }

  async deleteMessage(id: string): Promise<void> {
    const index = this.messages.findIndex((message) => message.id === id);
    if (index >= 0) this.messages.splice(index, 1);
  }

  async listRecentMessages(liveId: string, limit: number, excludedUserIds: string[]): Promise<LiveMessage[]> {
    return this.messages.filter((m) => m.liveId === liveId && !excludedUserIds.includes(m.userId)).slice(-limit);
  }

  async deleteMessages(liveId: string): Promise<void> {
    for (let i = this.messages.length - 1; i >= 0; i--) if (this.messages[i].liveId === liveId) this.messages.splice(i, 1);
  }

  async findInProgress(limit: number): Promise<Live[]> {
    return [...this.lives.values()].filter((live) => live.status === 'live').slice(0, limit);
  }
}

// Serveur vidéo simulé : salles ouvertes, participants connectés, jetons lisibles.
export class InMemoryLiveMedia extends LiveMedia {
  readonly publicUrl = 'ws://livekit.test';
  readonly rooms = new Set<string>();
  readonly connected = new Set<string>();
  failCreate = false;

  async createRoom(liveId: string): Promise<void> {
    if (this.failCreate) throw new Error('serveur vidéo indisponible');
    this.rooms.add(liveId);
  }

  async deleteRoom(liveId: string): Promise<void> {
    this.rooms.delete(liveId);
  }

  async listRooms(): Promise<string[]> {
    return [...this.rooms];
  }

  async isConnected(liveId: string, identity: string): Promise<boolean> {
    return this.connected.has(`${liveId}|${identity}`);
  }

  // Jeton lisible : salle, identité, droit de publier.
  async createToken(grant: { liveId: string; identity: string; canPublish: boolean }): Promise<string> {
    return `token:${grant.liveId}:${grant.identity}:${grant.canPublish ? 'publish' : 'subscribe'}`;
  }

  // Le test donne directement l'événement (la vérification de signature est celle du SDK).
  async receiveWebhook(body: string): Promise<LiveMediaEvent | null> {
    return JSON.parse(body) as LiveMediaEvent;
  }
}

export type RoomEvent =
  | { type: 'chatMessage'; liveId: string; messageId: string; content: string; author: string }
  | { type: 'chatMessageDeleted'; liveId: string; messageId: string }
  | { type: 'hearts'; liveId: string; count: number; total: number }
  | { type: 'gift'; liveId: string; sender: string; code: string; amount: number; giftsCount: number; giftsAmount: number }
  | { type: 'liveEnded'; liveId: string; reason: LiveEndReason };

export class InMemoryLiveRoomPublisher extends LiveRoomPublisher {
  readonly events: RoomEvent[] = [];

  async chatMessage(message: LiveMessage, author: User): Promise<void> {
    this.events.push({ type: 'chatMessage', liveId: message.liveId, messageId: message.id, content: message.content, author: author.id });
  }

  async chatMessageDeleted(liveId: string, messageId: string): Promise<void> {
    this.events.push({ type: 'chatMessageDeleted', liveId, messageId });
  }

  async hearts(liveId: string, count: number, total: number): Promise<void> {
    this.events.push({ type: 'hearts', liveId, count, total });
  }

  async gift(liveId: string, sender: User, gift: GiftDetails, totals: { giftsCount: number; giftsAmount: number }): Promise<void> {
    this.events.push({ type: 'gift', liveId, sender: sender.id, code: gift.code, amount: gift.amount, ...totals });
  }

  async liveEnded(liveId: string, reason: LiveEndReason): Promise<void> {
    this.events.push({ type: 'liveEnded', liveId, reason });
  }
}

export class InMemoryLiveLifecycleQueue extends LiveLifecycleQueue {
  readonly timeLimits = new Map<string, Date>();
  readonly hostChecks = new Map<string, number>();

  async scheduleTimeLimit(liveId: string, at: Date): Promise<void> {
    this.timeLimits.set(liveId, at);
  }

  async scheduleHostCheck(liveId: string, delayMs: number): Promise<void> {
    this.hostChecks.set(liveId, delayMs);
  }
}

// Service du live avec tous ses adaptateurs en mémoire. Identifiants ordonnés (comme des UUID v7) et lisibles.
export function inMemoryLive(
  users: UsersService,
  interactions: InteractionsService,
  notifications: NotificationsService,
  now: () => Date = () => new Date(),
) {
  const repository = new InMemoryLiveRepository();
  const media = new InMemoryLiveMedia();
  const room = new InMemoryLiveRoomPublisher();
  const lifecycle = new InMemoryLiveLifecycleQueue();
  const rateLimiter = new InMemoryRateLimiter(() => now().getTime());
  let sequence = 0;
  let guests = 0;
  const service = new LiveService(
    repository,
    media,
    room,
    lifecycle,
    users,
    interactions,
    notifications,
    rateLimiter,
    now,
    () => `00000000-0000-7000-a000-${String(++sequence).padStart(12, '0')}`,
    () => `invite-${++guests}`,
  );
  return { service, repository, media, room, lifecycle, rateLimiter };
}
