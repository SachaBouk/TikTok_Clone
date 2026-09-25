import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { RealtimeService } from './application/realtime.service';
import { AccessTokenVerifier } from './domain/access-token-verifier';
import { RealtimeBus } from './domain/realtime-bus';
import { AuthAccessTokenVerifier } from './infrastructure/auth-access-token-verifier';
import { RedisRealtimeBus } from './infrastructure/redis-realtime-bus';
import { RealtimeGateway } from './interfaces/realtime.gateway';

// Temps réel (ADR-011) : WebSocket natif authentifié au handshake, diffusion entre instances par Redis pub/sub.
// Les modules qui émettent des événements (videos, notifications) passent par RealtimeService, exporté.
// L'adaptateur WebSocket (RealtimeWsAdapter) est branché dans main.ts.
@Module({
  imports: [AuthModule],
  providers: [
    { provide: RealtimeBus, useClass: RedisRealtimeBus },
    { provide: AccessTokenVerifier, useClass: AuthAccessTokenVerifier },
    {
      provide: RealtimeService,
      useFactory: (bus: RealtimeBus, tokens: AccessTokenVerifier) => new RealtimeService(bus, tokens),
      inject: [RealtimeBus, AccessTokenVerifier],
    },
    RealtimeGateway,
  ],
  exports: [RealtimeService],
})
export class RealtimeModule {}
