import { readFileSync } from 'node:fs';

// Configuration APNs, lue depuis l'environnement (voir .env.example). Facultative : sans clé, les
// notifications sont seulement journalisées (LoggingPushSender). Incomplète : l'API refuse de démarrer.
export interface ApnsConfig {
  // Clé d'authentification APNs (.p8, PEM PKCS#8) et son identifiant, équipe Apple Developer.
  privateKey: string;
  keyId: string;
  teamId: string;
  // Bundle ID de l'app (en-tête apns-topic).
  topic: string;
  // Remplace les serveurs d'Apple (tests avec un faux serveur APNs, en h2c : http://localhost:…).
  hostOverride: string | null;
}

export function apnsConfigFromEnv(env: NodeJS.ProcessEnv = process.env): ApnsConfig | null {
  const keyId = env.APNS_KEY_ID || undefined;
  const teamId = env.APNS_TEAM_ID || undefined;
  const privateKey = env.APNS_KEY ? env.APNS_KEY.replace(/\\n/g, '\n') : env.APNS_KEY_FILE ? readFileSync(env.APNS_KEY_FILE, 'utf8') : undefined;
  if (!keyId && !teamId && !privateKey) return null;
  if (!keyId || !teamId || !privateKey) {
    throw new Error('Configuration APNs incomplète : APNS_KEY_ID, APNS_TEAM_ID et APNS_KEY (ou APNS_KEY_FILE) vont ensemble. Voir .env.example.');
  }
  const topic = env.APNS_TOPIC || env.APPLE_BUNDLE_ID;
  if (!topic) throw new Error('APNS_TOPIC ou APPLE_BUNDLE_ID manquant. Voir .env.example.');
  return { privateKey, keyId, teamId, topic, hostOverride: env.APNS_HOST || null };
}
