import type { ConnectionOptions } from 'bullmq';

// Connexion Redis des files BullMQ de l'API (ADR-012, ADR-014).
// Attention : BullMQ ouvre la connexion dès la construction d'une Queue ou d'un Worker. Ne les créer
// que dans onModuleInit ou au premier usage, jamais dans un constructeur ou une factory de provider :
// l'export OpenAPI construit les modules sans Redis.
export function queueConnection(): ConnectionOptions {
  const url = process.env.REDIS_URL;
  if (!url) throw new Error('REDIS_URL manquant. Voir .env.example.');
  return { url };
}
