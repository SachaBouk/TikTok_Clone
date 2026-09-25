import type { IncomingMessage } from 'node:http';
import { Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { OnGatewayConnection, OnGatewayDisconnect, WebSocketGateway, WebSocketServer } from '@nestjs/websockets';
import { WebSocket, type WebSocketServer as WsServer } from 'ws';
import { RealtimeService } from '../application/realtime.service';
import { CLOSE_SESSION_EXPIRED, HEARTBEAT_INTERVAL_MS, MAX_CLIENT_MESSAGE_BYTES, REALTIME_PATH } from '../domain/realtime';
import { handshakeSession } from './realtime-ws.adapter';

// Point d'entrée WebSocket (ADR-011) : ws://<hôte>:3000/realtime, sur le serveur HTTP de l'API.
// L'authentification a lieu avant, au handshake (RealtimeWsAdapter). Ici : enregistrement des connexions
// auprès du service, messages de l'app remis au service, et détection des connexions mortes (ping / pong).
@WebSocketGateway({ path: REALTIME_PATH, maxPayload: MAX_CLIENT_MESSAGE_BYTES })
export class RealtimeGateway implements OnGatewayConnection, OnGatewayDisconnect, OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger('Realtime');
  private readonly detach = new WeakMap<WebSocket, () => void>();
  private readonly alive = new WeakMap<WebSocket, boolean>();
  private heartbeat?: NodeJS.Timeout;

  @WebSocketServer()
  private readonly server!: WsServer;

  constructor(private readonly realtime: RealtimeService) {}

  // Échoue au démarrage si Redis est injoignable.
  async onModuleInit() {
    await this.realtime.start();
    this.heartbeat = setInterval(() => this.checkConnections(), HEARTBEAT_INTERVAL_MS);
  }

  async onModuleDestroy() {
    clearInterval(this.heartbeat);
    await this.realtime.stop();
  }

  handleConnection(client: WebSocket, request: IncomingMessage) {
    const session = handshakeSession(request);
    if (!session) return client.close(CLOSE_SESSION_EXPIRED, 'Access token requis');

    this.alive.set(client, true);
    client.on('pong', () => this.alive.set(client, true));
    client.on('message', (raw, isBinary) => {
      if (isBinary) return;
      this.realtime.receive(session.userId, raw.toString()).catch((error: Error) => this.logger.warn(`Message de l'app en échec : ${error.message}`));
    });
    this.detach.set(
      client,
      this.realtime.attach(
        {
          send: (message) => {
            if (client.readyState === WebSocket.OPEN) client.send(message);
          },
          close: (code, reason) => client.close(code, reason),
        },
        session,
      ),
    );
  }

  handleDisconnect(client: WebSocket) {
    this.detach.get(client)?.();
    this.detach.delete(client);
  }

  // Une connexion qui n'a pas répondu au ping précédent est coupée (réseau perdu sans fermeture propre).
  private checkConnections() {
    for (const client of this.server?.clients ?? []) {
      if (this.alive.get(client) === false) {
        this.logger.log('Connexion sans réponse au ping : coupée');
        client.terminate();
        continue;
      }
      this.alive.set(client, false);
      client.ping();
    }
  }
}
