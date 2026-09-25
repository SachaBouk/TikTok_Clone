import { Global, Injectable, Module, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Redis } from 'ioredis';

// Client Redis partagé de l'API (ADR-014 : cache du feed, sessions, compteurs), injecté par sa classe `Redis`.
// À n'utiliser que depuis les adaptateurs `infrastructure/` des modules (ADR-003).
// Les files BullMQ ont leurs propres connexions (src/queue).
function createRedis(): Redis {
  const url = process.env.REDIS_URL;
  if (!url) throw new Error('REDIS_URL manquant. Voir .env.example.');
  // `lazyConnect` : aucune connexion à la construction (l'export OpenAPI construit les modules sans Redis).
  return new Redis(url, { lazyConnect: true, maxRetriesPerRequest: 3 });
}

@Injectable()
class RedisLifecycle implements OnModuleInit, OnModuleDestroy {
  constructor(private readonly redis: Redis) {}

  // Échoue au démarrage si Redis est injoignable, plutôt qu'à la première requête.
  async onModuleInit() {
    await this.redis.connect();
    await this.redis.ping();
  }

  async onModuleDestroy() {
    await this.redis.quit();
  }
}

@Global()
@Module({
  providers: [{ provide: Redis, useFactory: createRedis }, RedisLifecycle],
  exports: [Redis],
})
export class RedisModule {}
