import type { RealtimeEventDto } from '@repo/shared';
import type { AccessTokenVerifier } from '../domain/access-token-verifier';
import {
  CLOSE_GOING_AWAY,
  CLOSE_SESSION_EXPIRED,
  type ClientMessageHandler,
  type RealtimeConnection,
  type RealtimeMessage,
  type RealtimeSession,
} from '../domain/realtime';
import type { RealtimeBus } from '../domain/realtime-bus';

// Service applicatif du temps réel (ADR-011, ADR-003).
// - Les autres modules envoient un événement à un compte (`sendToUser`) ; il passe par le bus (Redis pub/sub)
//   pour atteindre l'instance qui détient la connexion.
// - Chaque instance remet les messages du bus à ses propres connexions (tous les appareils du compte).
// - Une connexion est fermée à l'expiration de son access token (4001) : l'app se reconnecte avec un token neuf.
//   Une session révoquée ou un compte supprimé ne reçoit donc plus rien au bout de 15 minutes au plus.
export class RealtimeService {
  private readonly connections = new Map<string, Set<RealtimeConnection>>();
  private readonly clientHandlers = new Map<string, ClientMessageHandler>();
  private unsubscribe: (() => Promise<void>) | null = null;

  constructor(
    private readonly bus: RealtimeBus,
    private readonly tokens: AccessTokenVerifier,
    private readonly now: () => Date = () => new Date(),
  ) {}

  // Handshake : compte et expiration, ou null (token absent, invalide ou expiré → HTTP 401).
  authenticate(accessToken: string | null): Promise<RealtimeSession | null> {
    return accessToken ? this.tokens.verify(accessToken) : Promise.resolve(null);
  }

  // Enregistre une connexion ouverte. Renvoie la fonction à appeler à sa fermeture.
  attach(connection: RealtimeConnection, session: RealtimeSession): () => void {
    const remaining = session.expiresAt.getTime() - this.now().getTime();
    if (remaining <= 0) {
      connection.close(CLOSE_SESSION_EXPIRED, 'Access token expiré');
      return () => {};
    }

    const own = this.connections.get(session.userId) ?? new Set<RealtimeConnection>();
    own.add(connection);
    this.connections.set(session.userId, own);
    const expiry = setTimeout(() => connection.close(CLOSE_SESSION_EXPIRED, 'Access token expiré'), remaining);

    return () => {
      clearTimeout(expiry);
      own.delete(connection);
      if (own.size === 0 && this.connections.get(session.userId) === own) this.connections.delete(session.userId);
    };
  }

  // Au mieux : sans connexion ouverte, ou si la diffusion échoue, l'événement est perdu.
  // À la reconnexion, l'app relit l'état par l'API REST.
  sendToUser(userId: string, event: RealtimeEventDto): Promise<void> {
    return this.bus.publish({ userId, event });
  }

  // Ferme toutes les connexions du compte, sur toutes les instances (suspension, ADR-037). Code 4001 : l'app tente
  // de rafraîchir sa session, refusée, et repasse en invité. Au mieux, comme les événements.
  disconnectUser(userId: string): Promise<void> {
    return this.bus.publish({ userId, disconnect: true });
  }

  // Un module traite un type de message de l'app (ex. messaging : `typing`). Le module realtime ne dépend
  // ainsi d'aucun module émetteur.
  onClientMessage(event: string, handler: ClientMessageHandler): void {
    this.clientHandlers.set(event, handler);
  }

  // Message de l'app `{ event, data }`, remis au gestionnaire de son type ; tout le reste est ignoré.
  async receive(userId: string, raw: string): Promise<void> {
    let message: unknown;
    try {
      message = JSON.parse(raw);
    } catch {
      return;
    }
    if (!message || typeof message !== 'object') return;
    const { event, data } = message as { event?: unknown; data?: unknown };
    const handler = typeof event === 'string' ? this.clientHandlers.get(event) : undefined;
    if (handler) await handler(userId, data);
  }

  // Démarre l'écoute du bus (au démarrage de l'instance).
  async start(): Promise<void> {
    if (!this.unsubscribe) this.unsubscribe = await this.bus.subscribe((message) => this.deliver(message));
  }

  // Arrêt de l'instance : les apps connectées se reconnecteront à une autre (ou à celle-ci, relancée).
  async stop(): Promise<void> {
    for (const own of this.connections.values()) {
      for (const connection of own) connection.close(CLOSE_GOING_AWAY, 'Arrêt du serveur');
    }
    this.connections.clear();
    await this.unsubscribe?.();
    this.unsubscribe = null;
  }

  // Nombre de connexions ouvertes sur cette instance.
  get connectionCount(): number {
    let count = 0;
    for (const own of this.connections.values()) count += own.size;
    return count;
  }

  private deliver(message: RealtimeMessage): void {
    const own = this.connections.get(message.userId);
    if (!own) return;
    if ('disconnect' in message) {
      for (const connection of [...own]) connection.close(CLOSE_SESSION_EXPIRED, 'Session révoquée');
      return;
    }
    const payload = JSON.stringify(message.event);
    for (const connection of own) connection.send(payload);
  }
}
