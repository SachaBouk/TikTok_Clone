import { Injectable, Logger } from '@nestjs/common';
import { Redis } from 'ioredis';
import type { RealtimeMessage } from '../domain/realtime';
import { RealtimeBus } from '../domain/realtime-bus';

const CHANNEL = 'realtime:events';

// Redis pub/sub (ADR-011) : un seul canal, écouté par toutes les instances de l'API ; chacune ne remet
// un message qu'aux connexions qu'elle détient. Publication par le client partagé (RedisModule) ;
// l'écoute exige sa propre connexion (un client abonné ne peut plus envoyer d'autres commandes).
@Injectable()
export class RedisRealtimeBus extends RealtimeBus {
  private readonly logger = new Logger('RealtimeBus');

  constructor(private readonly redis: Redis) {
    super();
  }

  async publish(message: RealtimeMessage): Promise<void> {
    try {
      await this.redis.publish(CHANNEL, JSON.stringify(message));
    } catch (error) {
      this.logger.warn(`Événement ${message.event.event} non diffusé : ${(error as Error).message}`);
    }
  }

  // Connexion créée ici, au démarrage de l'écoute, et non à la construction : l'export OpenAPI
  // construit les modules sans les initialiser et ne doit pas se connecter à Redis.
  async subscribe(handler: (message: RealtimeMessage) => void): Promise<() => Promise<void>> {
    const subscriber = this.redis.duplicate();
    subscriber.on('message', (_channel: string, raw: string) => {
      try {
        handler(JSON.parse(raw) as RealtimeMessage);
      } catch (error) {
        this.logger.error(`Message temps réel ignoré : ${(error as Error).message}`);
      }
    });
    // Après une coupure, ioredis se reconnecte et se réabonne tout seul ; les messages publiés
    // pendant la coupure sont perdus (pub/sub ne les conserve pas).
    subscriber.on('error', (error: Error) => this.logger.warn(`Abonnement Redis : ${error.message}`));
    await subscriber.subscribe(CHANNEL);
    return async () => {
      await subscriber.quit();
    };
  }
}
