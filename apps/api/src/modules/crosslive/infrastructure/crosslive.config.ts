// Configuration du Live commun (ADR-079), lue dans le `.env` racine. Facultative : sans secret, l'API démarre et
// `POST /live/participant-token` répond 503.
export interface CrossLiveConfig {
  // Identifiant de notre App membre chez echimine (`iss` du jeton).
  appId: string;
  // Secret HS256 transmis en privé par echimine ; jamais versionné.
  secret: string | null;
}

export function crossLiveConfigFromEnv(env: NodeJS.ProcessEnv = process.env): CrossLiveConfig {
  const secret = env.LIVE_SDK_TOKEN_SECRET?.trim();
  return { appId: env.LIVE_SDK_APP_ID?.trim() || 'tiktok', secret: secret ? secret : null };
}
