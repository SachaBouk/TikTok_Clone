import { Global, Module } from '@nestjs/common';
import { RateLimiter } from './rate-limiter';
import { RedisRateLimiter } from './redis-rate-limiter';

// Limites de débit partagées (messagerie, connexion, partages), dans le Redis de l'API (RedisModule, global).
// Les modules injectent le port `RateLimiter` dans leur service par la factory de leur module.
@Global()
@Module({
  providers: [{ provide: RateLimiter, useClass: RedisRateLimiter }],
  exports: [RateLimiter],
})
export class RateLimitModule {}
