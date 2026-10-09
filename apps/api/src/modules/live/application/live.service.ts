import { randomUUID } from 'node:crypto';
import type { InteractionsService } from '../../interactions/application/interactions.service';
import type { NotificationsService } from '../../notifications/application/notifications.service';
import type { UsersService } from '../../users/application/users.service';
import type { User } from '../../users/domain/user';
import { UserNotFoundError } from '../../users/domain/user.errors';
import type { RateLimiter } from '../../../rate-limit/rate-limiter';
// UUID v7 (ordonné dans le temps, comme ceux de Prisma) : l'identifiant du live sert aussi de nom de salle.
import { newStoryId as newUuidV7 } from '../../stories/domain/story-id';
import {
  durationSeconds,
  guestIdentity,
  HOST_FIRST_CONNECT_GRACE_MS,
  HOST_RECONNECT_GRACE_MS,
  isInProgress,
  type Live,
  type LiveEndReason,
  type LiveMessage,
  LIVE_HEARTS_RATE_LIMITS,
  LIVE_MAINTENANCE_BATCH_SIZE,
  LIVE_MAX_DURATION_MS,
  LIVE_MESSAGE_RATE_LIMITS,
  LIVE_START_RATE_LIMITS,
  LIVE_TOKEN_TTL_SECONDS,
  type LiveStats,
  MAX_FOLLOWING_LIVES,
  MAX_HEARTS_PER_BATCH,
  MAX_LIVE_MESSAGE_LENGTH,
  MAX_LIVE_TITLE_LENGTH,
  RECENT_LIVE_MESSAGES,
  sanitizeTitle,
  timeLimitOf,
  userIdentity,
  userIdOfIdentity,
} from '../domain/live';
import {
  InvalidHeartsCountError,
  InvalidLiveMessageError,
  InvalidLiveTitleError,
  LiveEndedError,
  LiveMediaUnavailableError,
  LiveMessageForbiddenError,
  LiveMessageNotFoundError,
  LiveNotFoundError,
  OwnLiveError,
  TooManyLiveActionsError,
} from '../domain/live.errors';
import type { GiftDetails } from '../domain/live-events';
import type { LiveLifecycleQueue, LiveMedia, LiveMediaEvent, LiveRoomPublisher } from '../domain/live-media';
import type { LiveRepository } from '../domain/live.repository';

// Un live tel qu'un compte le voit : son auteur, et ses chiffres si c'est le sien.
export interface LiveItem {
  live: Live;
  host: User;
  stats?: LiveStats;
}

export interface LiveMessageWithAuthor {
  message: LiveMessage;
  author: User;
}

// Accès à la salle du serveur vidéo.
export interface LiveConnection {
  item: LiveItem;
  role: 'host' | 'viewer';
  url: string;
  token: string;
  recentMessages: LiveMessageWithAuthor[];
}

// Live où l'on peut envoyer un cadeau (module wallet) : en cours, visible, d'un autre compte.
export interface GiftableLive {
  live: Live;
  hostId: string;
}

export interface LiveMaintenanceReport {
  ended: number;
  // Auteurs absents de leur salle : vérification (re)programmée.
  hostChecks: number;
}

// Service applicatif du module live (ADR-053, ADR-003).
// - La vidéo passe par le serveur LiveKit (port `LiveMedia`) : l'API ouvre et ferme la salle, et délivre les jetons
//   d'accès (publier pour l'auteur, regarder pour les autres, invités compris).
// - Chat, cœurs et cadeaux passent par l'API (contrôles, limites), puis sont diffusés dans la salle (`LiveRoomPublisher`).
// - Fin : par l'auteur, à 2 h, auteur déconnecté plus de 60 s, par un administrateur, à la suspension du compte.
// - Visible de tous, sauf des comptes bloqués dans un sens ou dans l'autre ; masqué si son auteur est suspendu.
export class LiveService {
  constructor(
    private readonly lives: LiveRepository,
    private readonly media: LiveMedia,
    private readonly room: LiveRoomPublisher,
    private readonly lifecycle: LiveLifecycleQueue,
    private readonly users: UsersService,
    private readonly interactions: InteractionsService,
    private readonly notifications: NotificationsService,
    private readonly rateLimiter: RateLimiter,
    private readonly now: () => Date = () => new Date(),
    private readonly makeLiveId: () => string = () => newUuidV7(),
    private readonly makeGuestId: () => string = () => randomUUID(),
  ) {}

  // ─── Auteur ────────────────────────────────────────────────────────────────

  // Lance un live : salle ouverte, abonnés prévenus, jeton de l'auteur. Un live déjà en cours est repris (app relancée
  // pendant le live), sans nouvelle salle ni notification.
  async start(userId: string, input: { title?: string | null }): Promise<LiveConnection> {
    const title = sanitizeTitle(input.title);
    if (title !== null && title.length > MAX_LIVE_TITLE_LENGTH) throw new InvalidLiveTitleError();
    const host = await this.users.getById(userId);
    const existing = await this.lives.findInProgressByUser(userId);
    if (existing) return this.connection(existing, host, 'host', userIdentity(userId), []);

    const retryAfter = await this.rateLimiter.consume(`live-start:${userId}`, LIVE_START_RATE_LIMITS);
    if (retryAfter !== null) throw new TooManyLiveActionsError(retryAfter, 'starts');

    const live = await this.lives.create({ id: this.makeLiveId(), userId, title, startedAt: this.now() });
    // Lancement simultané : l'autre requête a créé le live, on le reprend.
    if (!live) return this.start(userId, input);
    try {
      await this.media.createRoom(live.id);
    } catch {
      await this.lives.end(live.id, 'disconnected', this.now());
      throw new LiveMediaUnavailableError();
    }
    await this.schedule(() => this.lifecycle.scheduleTimeLimit(live.id, timeLimitOf(live)));
    await this.schedule(() => this.lifecycle.scheduleHostCheck(live.id, HOST_FIRST_CONNECT_GRACE_MS));
    void this.notifyFollowers(live);
    return this.connection(live, host, 'host', userIdentity(userId), []);
  }

  // Fin par l'auteur. Idempotent : un live déjà terminé est rendu tel quel.
  async stop(userId: string, liveId: string): Promise<LiveItem> {
    const live = await this.lives.findById(liveId);
    if (!live || live.userId !== userId) throw new LiveNotFoundError(liveId);
    const ended = (await this.endLive(live, 'host')) ?? live;
    return this.withStats(ended, await this.users.getById(userId));
  }

  // ─── Spectateurs ───────────────────────────────────────────────────────────

  // Un live, en cours ou terminé, s'il est visible du lecteur ; ses chiffres pour son auteur.
  async getLive(liveId: string, viewerId: string | null): Promise<LiveItem> {
    const live = await this.visibleLive(liveId, viewerId);
    const host = await this.users.getById(live.userId);
    return live.userId === viewerId ? this.withStats(live, host) : { live, host };
  }

  // Rejoindre la salle : jeton de spectateur (de l'auteur s'il revient), derniers messages du chat.
  async join(liveId: string, viewerId: string | null): Promise<LiveConnection> {
    const live = await this.visibleLive(liveId, viewerId);
    if (!isInProgress(live)) throw new LiveEndedError();
    const host = await this.users.getById(live.userId);
    const recent = await this.recentMessages(live, viewerId);
    if (viewerId === live.userId) return this.connection(live, host, 'host', userIdentity(viewerId), recent);
    const identity = viewerId ? userIdentity(viewerId) : guestIdentity(this.makeGuestId());
    return this.connection(live, host, 'viewer', identity, recent);
  }

  // Lives en cours des comptes suivis (rangée de la boîte de réception), du plus récent au plus ancien.
  async listFollowingLives(viewerId: string): Promise<LiveItem[]> {
    const following = await this.interactions.listVisibleFollowingIds(viewerId);
    if (following.length === 0) return [];
    const lives = (await this.lives.findInProgressByUsers(following)).slice(0, MAX_FOLLOWING_LIVES);
    return this.withHosts(lives);
  }

  // Profils (et anneau « EN DIRECT ») : live en cours de chacun de ces comptes, s'il est visible du lecteur.
  async getLiveRings(userIds: string[], viewerId: string | null): Promise<Map<string, Live>> {
    const unique = [...new Set(userIds)];
    if (unique.length === 0) return new Map();
    const hidden = await this.interactions.getHiddenAccountIds(viewerId);
    const visible = unique.filter((id) => !hidden.has(id));
    if (visible.length === 0) return new Map();
    return new Map((await this.lives.findInProgressByUsers(visible)).map((live) => [live.userId, live]));
  }

  // ─── Chat, cœurs ───────────────────────────────────────────────────────────

  async sendMessage(userId: string, liveId: string, content: string): Promise<LiveMessageWithAuthor> {
    const text = content.trim();
    if (text.length === 0 || text.length > MAX_LIVE_MESSAGE_LENGTH) throw new InvalidLiveMessageError();
    const live = await this.visibleLive(liveId, userId);
    if (!isInProgress(live)) throw new LiveEndedError();
    const retryAfter = await this.rateLimiter.consume(`live-message:${userId}`, LIVE_MESSAGE_RATE_LIMITS);
    if (retryAfter !== null) throw new TooManyLiveActionsError(retryAfter, 'messages');
    const message = await this.lives.addMessage({ liveId: live.id, userId, content: text, createdAt: this.now() });
    const author = await this.users.getById(userId);
    await this.broadcast(() => this.room.chatMessage(message, author));
    return { message, author };
  }

  // Retrait par l'auteur du message ou celui du live, annoncé dans la salle.
  async deleteMessage(userId: string, liveId: string, messageId: string): Promise<void> {
    const live = await this.visibleLive(liveId, userId);
    const message = await this.lives.findMessage(messageId);
    if (!message || message.liveId !== live.id) throw new LiveMessageNotFoundError(messageId);
    if (message.userId !== userId && live.userId !== userId) throw new LiveMessageForbiddenError();
    await this.lives.deleteMessage(message.id);
    await this.broadcast(() => this.room.chatMessageDeleted(live.id, message.id));
  }

  // Cœurs envoyés par lots ; renvoie le total du live. Pas sur son propre live.
  async sendHearts(userId: string, liveId: string, count: number): Promise<number> {
    if (!Number.isInteger(count) || count < 1 || count > MAX_HEARTS_PER_BATCH) throw new InvalidHeartsCountError();
    const live = await this.visibleLive(liveId, userId);
    if (!isInProgress(live)) throw new LiveEndedError();
    if (live.userId === userId) throw new OwnLiveError();
    const retryAfter = await this.rateLimiter.consume(`live-hearts:${userId}`, LIVE_HEARTS_RATE_LIMITS);
    if (retryAfter !== null) throw new TooManyLiveActionsError(retryAfter, 'hearts');
    const total = await this.lives.addHearts(live.id, count);
    await this.broadcast(() => this.room.hearts(live.id, count, total));
    return total;
  }

  // ─── Pour les autres modules (ADR-003) ─────────────────────────────────────

  // Portefeuille : live où `senderId` peut envoyer un cadeau. Erreurs : introuvable ou masqué (404), terminé (409), le
  // sien (400). Les blocages sont vérifiés par le portefeuille, comme pour les vidéos.
  async getGiftableLive(senderId: string, liveId: string): Promise<GiftableLive> {
    const live = await this.lives.findById(liveId);
    if (!live || (await this.interactions.getHiddenAccountIds(null)).has(live.userId)) throw new LiveNotFoundError(liveId);
    if (!isInProgress(live)) throw new LiveEndedError();
    if (live.userId === senderId) throw new OwnLiveError();
    return { live, hostId: live.userId };
  }

  // Portefeuille : cadeau débité, compté pour le live et annoncé dans la salle (au mieux).
  async recordGift(liveId: string, sender: string, gift: GiftDetails): Promise<void> {
    const totals = await this.lives.addGift(liveId, gift.amount);
    const user = await this.users.getById(sender);
    await this.broadcast(() => this.room.gift(liveId, user, gift, totals));
  }

  // Messagerie (live partagé), signalements : un live en cours, visible du lecteur.
  async getVisibleLive(viewerId: string | null, liveId: string): Promise<Live> {
    const live = await this.visibleLive(liveId, viewerId);
    if (!isInProgress(live)) throw new LiveNotFoundError(liveId);
    return live;
  }

  // Messagerie : lives parmi `ids` visibles du lecteur, avec leur auteur (en cours ou terminés).
  async getLivePreviews(ids: string[], viewerId: string): Promise<Map<string, LiveItem>> {
    const unique = [...new Set(ids)];
    if (unique.length === 0) return new Map();
    const [lives, hidden] = await Promise.all([this.lives.findByIds(unique), this.interactions.getHiddenAccountIds(viewerId)]);
    const items = await this.withHosts(lives.filter((live) => !hidden.has(live.userId)));
    return new Map(items.map((item) => [item.live.id, item]));
  }

  // Backoffice (signalements) : lives existants parmi `ids`, avec leur auteur.
  async getLivesByIds(ids: string[]): Promise<LiveItem[]> {
    const unique = [...new Set(ids)];
    if (unique.length === 0) return [];
    const lives = await this.lives.findByIds(unique);
    const hosts = new Map((await this.users.getByIds(lives.map((live) => live.userId))).map((user) => [user.id, user]));
    return Promise.all(
      lives.flatMap((live) => {
        const host = hosts.get(live.userId);
        return host ? [this.withStats(live, host)] : [];
      }),
    );
  }

  // Arrêt par un administrateur (signalement, ADR-038). Renvoie faux si le live était déjà terminé.
  async removeLive(liveId: string): Promise<boolean> {
    const live = await this.lives.findById(liveId);
    if (!live) throw new LiveNotFoundError(liveId);
    return (await this.endLive(live, 'moderation')) !== null;
  }

  // Suspension du compte (ADR-037) : son live en cours s'arrête.
  async endForSuspension(userId: string): Promise<void> {
    const live = await this.lives.findInProgressByUser(userId);
    if (live) await this.endLive(live, 'suspension');
  }

  // Avant la suppression d'un compte (écouteur de UsersService) : sa salle est fermée ; la cascade emporte ses lives.
  async closeRoomsOf(userId: string): Promise<void> {
    const live = await this.lives.findInProgressByUser(userId);
    if (!live) return;
    await this.broadcast(() => this.room.liveEnded(live.id, 'host'));
    await this.closeRoom(live.id);
  }

  // ─── Serveur vidéo et jobs ─────────────────────────────────────────────────

  // Webhook du serveur vidéo : spectateurs arrivés (total, pic), départ ou retour de l'auteur, salle fermée.
  async handleMediaEvent(event: LiveMediaEvent): Promise<void> {
    const live = await this.lives.findById(event.liveId);
    if (!live || !isInProgress(live)) return;
    switch (event.type) {
      case 'participantJoined':
        if (userIdOfIdentity(event.identity) === live.userId) return;
        await this.lives.recordViewer(live.id, event.identity, this.now());
        // Le compte de la salle inclut l'auteur.
        await this.lives.raisePeakViewers(live.id, Math.max(0, event.participantsCount - 1));
        return;
      case 'participantLeft':
        if (userIdOfIdentity(event.identity) === live.userId) {
          await this.schedule(() => this.lifecycle.scheduleHostCheck(live.id, HOST_RECONNECT_GRACE_MS));
        }
        return;
      case 'roomFinished':
        await this.endLive(live, 'disconnected');
        return;
    }
  }

  // Vérification programmée : l'auteur n'est pas (re)venu dans la salle, le live s'arrête.
  async checkHost(liveId: string): Promise<boolean> {
    const live = await this.lives.findById(liveId);
    if (!live || !isInProgress(live)) return false;
    if (await this.media.isConnected(live.id, userIdentity(live.userId))) return false;
    return (await this.endLive(live, 'disconnected')) !== null;
  }

  // Durée maximale atteinte.
  async reachTimeLimit(liveId: string): Promise<boolean> {
    const live = await this.lives.findById(liveId);
    if (!live || !isInProgress(live)) return false;
    return (await this.endLive(live, 'timeLimit')) !== null;
  }

  // Maintenance (toutes les 5 min) : lives au-delà de la durée maximale (job perdu), lives dont la salle n'existe plus
  // (serveur vidéo redémarré), lives dont l'auteur n'est pas dans la salle (vérification reprogrammée : job perdu). Un
  // live lancé depuis moins de 2 min est laissé à sa vérification programmée.
  async runMaintenance(): Promise<LiveMaintenanceReport> {
    const now = this.now();
    const lives = await this.lives.findInProgress(LIVE_MAINTENANCE_BATCH_SIZE);
    if (lives.length === 0) return { ended: 0, hostChecks: 0 };
    const rooms = new Set(await this.media.listRooms());
    let ended = 0;
    let hostChecks = 0;
    for (const live of lives) {
      const age = now.getTime() - live.startedAt.getTime();
      if (age >= LIVE_MAX_DURATION_MS) {
        if (await this.endLive(live, 'timeLimit')) ended++;
      } else if (age < HOST_FIRST_CONNECT_GRACE_MS) {
        continue;
      } else if (!rooms.has(live.id)) {
        if (await this.endLive(live, 'disconnected')) ended++;
      } else if (!(await this.media.isConnected(live.id, userIdentity(live.userId)))) {
        await this.schedule(() => this.lifecycle.scheduleHostCheck(live.id, HOST_RECONNECT_GRACE_MS));
        hostChecks++;
      }
    }
    return { ended, hostChecks };
  }

  // ─── Interne ───────────────────────────────────────────────────────────────

  // Fin d'un live en cours : enregistrée (une seule fois), annoncée dans la salle, salle fermée, chat supprimé.
  private async endLive(live: Live, reason: LiveEndReason): Promise<Live | null> {
    const ended = await this.lives.end(live.id, reason, this.now());
    if (!ended) return null;
    await this.broadcast(() => this.room.liveEnded(live.id, reason));
    await this.closeRoom(live.id);
    await this.lives.deleteMessages(live.id);
    return ended;
  }

  private async closeRoom(liveId: string): Promise<void> {
    try {
      await this.media.deleteRoom(liveId);
    } catch {
      // Salle restée ouverte : sans auteur, elle se ferme d'elle-même ; aucun jeton neuf n'y donne plus accès.
    }
  }

  // Live visible du lecteur (invité si null) : ni masqué (blocage dans un sens ou dans l'autre), ni d'un compte suspendu.
  private async visibleLive(liveId: string, viewerId: string | null): Promise<Live> {
    const live = await this.lives.findById(liveId);
    if (!live) throw new LiveNotFoundError(liveId);
    if (live.userId !== viewerId && (await this.interactions.getHiddenAccountIds(viewerId)).has(live.userId)) throw new LiveNotFoundError(liveId);
    return live;
  }

  private async connection(
    live: Live,
    host: User,
    role: 'host' | 'viewer',
    identity: string,
    recent: LiveMessageWithAuthor[],
  ): Promise<LiveConnection> {
    const viewer = role === 'host' ? host : null;
    const token = await this.media.createToken({
      liveId: live.id,
      identity,
      name: viewer?.displayName ?? (await this.displayNameOf(identity)),
      canPublish: role === 'host',
      ttlSeconds: LIVE_TOKEN_TTL_SECONDS,
    });
    const item = role === 'host' ? await this.withStats(live, host) : { live, host };
    return { item, role, url: this.media.publicUrl, token, recentMessages: recent };
  }

  private async displayNameOf(identity: string): Promise<string> {
    const userId = userIdOfIdentity(identity);
    if (!userId) return 'Invité';
    try {
      return (await this.users.getById(userId)).displayName;
    } catch (error) {
      if (error instanceof UserNotFoundError) return 'Invité';
      throw error;
    }
  }

  private async recentMessages(live: Live, viewerId: string | null): Promise<LiveMessageWithAuthor[]> {
    const hidden = [...(await this.interactions.getHiddenAccountIds(viewerId))];
    const messages = await this.lives.listRecentMessages(live.id, RECENT_LIVE_MESSAGES, hidden);
    const authors = new Map((await this.users.getByIds(messages.map((m) => m.userId))).map((user) => [user.id, user]));
    return messages.flatMap((message) => {
      const author = authors.get(message.userId);
      return author ? [{ message, author }] : [];
    });
  }

  private async withStats(live: Live, host: User): Promise<LiveItem> {
    const viewersCount = await this.lives.countViewers(live.id, userIdentity(live.userId));
    return {
      live,
      host,
      stats: {
        durationSeconds: durationSeconds(live, this.now()),
        peakViewers: live.peakViewers,
        viewersCount,
        heartsCount: live.heartsCount,
        giftsCount: live.giftsCount,
        giftsAmount: live.giftsAmount,
      },
    };
  }

  private async withHosts(lives: Live[]): Promise<LiveItem[]> {
    const hosts = new Map((await this.users.getByIds(lives.map((live) => live.userId))).map((user) => [user.id, user]));
    return lives.flatMap((live) => {
      const host = hosts.get(live.userId);
      return host ? [{ live, host }] : [];
    });
  }

  // Abonnés prévenus (activité et push), au mieux et sans faire attendre le lancement : une notification par abonné.
  private async notifyFollowers(live: Live): Promise<void> {
    try {
      const followers = await this.interactions.listVisibleFollowerIds(live.userId);
      for (const recipientId of followers) {
        await this.notifications.notify({ type: 'live', actorId: live.userId, recipientId, liveId: live.id }).catch(() => undefined);
      }
    } catch {
      // Abonnés non prévenus : le live est lancé quand même, et visible dans leur rangée.
    }
  }

  // Événements de la salle : au mieux (serveur vidéo indisponible, l'action est faite quand même).
  private async broadcast(send: () => Promise<void>): Promise<void> {
    try {
      await send();
    } catch {
      // Les spectateurs relisent l'état à leur prochaine arrivée.
    }
  }

  // Jobs différés : au mieux ; la maintenance rattrape un job perdu (Redis indisponible).
  private async schedule(run: () => Promise<void>): Promise<void> {
    try {
      await run();
    } catch {
      // Rattrapé par `runMaintenance`.
    }
  }
}
