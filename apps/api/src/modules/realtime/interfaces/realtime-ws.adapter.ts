import type { IncomingMessage } from 'node:http';
import type { INestApplicationContext } from '@nestjs/common';
import { WsAdapter } from '@nestjs/platform-ws';
import type { RealtimeService } from '../application/realtime.service';
import type { RealtimeSession } from '../domain/realtime';

// Session posée sur la requête de handshake, relue par RealtimeGateway.handleConnection.
const SESSION = Symbol('realtimeSession');
type HandshakeRequest = IncomingMessage & { [SESSION]?: RealtimeSession };

export function handshakeSession(request: IncomingMessage): RealtimeSession | undefined {
  return (request as HandshakeRequest)[SESSION];
}

// Adaptateur WebSocket natif (ADR-011) qui authentifie au handshake : sans access token valide
// (`Authorization: Bearer …`), la mise à niveau est refusée en HTTP 401, avant toute connexion.
// L'app rafraîchit alors sa paire de tokens et réessaie. Branché dans main.ts.
export class RealtimeWsAdapter extends WsAdapter {
  constructor(
    app: INestApplicationContext,
    private readonly realtime: RealtimeService,
  ) {
    super(app);
  }

  override create(port: number, options: Record<string, unknown> & { path?: string } = {}) {
    return super.create(port, {
      ...options,
      verifyClient: (
        info: { req: IncomingMessage },
        done: (verified: boolean, code?: number, message?: string) => void,
      ) => {
        this.realtime.authenticate(bearerToken(info.req)).then(
          (session) => {
            if (!session) return done(false, 401, 'Unauthorized');
            (info.req as HandshakeRequest)[SESSION] = session;
            done(true);
          },
          () => done(false, 500, 'Internal Server Error'),
        );
      },
    });
  }
}

function bearerToken(request: IncomingMessage): string | null {
  const match = /^Bearer (\S+)$/i.exec(request.headers.authorization ?? '');
  return match?.[1] ?? null;
}
