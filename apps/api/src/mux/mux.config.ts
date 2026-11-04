import { createPrivateKey, type KeyObject } from 'node:crypto';

export type VideoProvider = 'local' | 'mux';

// Configuration de Mux (ADR-074), lue depuis l'environnement (voir .env.example).
// - `VIDEO_PROVIDER` : `local` (par défaut, pipeline maison) ou `mux` (nouveaux envois chez Mux).
// - Jeton d'API, secret des webhooks et clé de signature : facultatifs en `local` (vidéos Mux déjà publiées : lecture,
//   suppression, webhooks), tous exigés en `mux` (l'API refuse de démarrer sinon).
export class MuxConfig {
  constructor(
    readonly provider: VideoProvider,
    readonly apiUrl: string,
    readonly tokenId: string | null,
    readonly tokenSecret: string | null,
    readonly webhookSecret: string | null,
    // Clé de signature des URLs de lecture (vidéos privées) : identifiant et clé privée RSA.
    readonly signingKeyId: string | null,
    readonly signingKey: KeyObject | null,
  ) {}

  get apiConfigured(): boolean {
    return this.tokenId !== null && this.tokenSecret !== null;
  }

  static fromEnv(env: NodeJS.ProcessEnv = process.env): MuxConfig {
    const value = (name: string) => env[name]?.trim() || null;
    const provider = value('VIDEO_PROVIDER') ?? 'local';
    if (provider !== 'local' && provider !== 'mux') throw new Error(`VIDEO_PROVIDER doit valoir local ou mux (reçu : ${provider}).`);
    const signingKey = value('MUX_SIGNING_KEY');
    const config = new MuxConfig(
      provider,
      (value('MUX_API_URL') ?? 'https://api.mux.com').replace(/\/+$/, ''),
      value('MUX_TOKEN_ID'),
      value('MUX_TOKEN_SECRET'),
      value('MUX_WEBHOOK_SECRET'),
      value('MUX_SIGNING_KEY_ID'),
      signingKey ? parseSigningKey(signingKey) : null,
    );
    if (provider === 'mux') {
      const missing = ['MUX_TOKEN_ID', 'MUX_TOKEN_SECRET', 'MUX_WEBHOOK_SECRET', 'MUX_SIGNING_KEY_ID', 'MUX_SIGNING_KEY'].filter(
        (name) => !value(name),
      );
      if (missing.length > 0) throw new Error(`VIDEO_PROVIDER=mux : ${missing.join(', ')} manquant(s). Voir .env.example.`);
    }
    return config;
  }
}

// Clé privée donnée par Mux : PEM encodé en base64 (tableau de bord ou API), ou PEM tel quel.
function parseSigningKey(raw: string): KeyObject {
  const pem = raw.includes('-----BEGIN') ? raw.replace(/\\n/g, '\n') : Buffer.from(raw, 'base64').toString('utf8');
  try {
    return createPrivateKey(pem);
  } catch {
    throw new Error('MUX_SIGNING_KEY illisible : la clé privée de signature de Mux, encodée en base64, est attendue.');
  }
}
