// Serveur vidéo LiveKit (ADR-053) : auto-hébergé (Docker en local) ou LiveKit Cloud, sans changer le code.
export class LiveKitConfig {
  constructor(
    // Adresse appelée par l'API (API REST du serveur : salles, données) ; http(s).
    readonly apiUrl: string,
    // Adresse donnée à l'app (WebSocket) : ws(s). Sur un iPhone physique, l'IP du Mac.
    readonly publicUrl: string,
    readonly apiKey: string,
    readonly apiSecret: string,
  ) {}

  static fromEnv(env: NodeJS.ProcessEnv = process.env): LiveKitConfig {
    const missing = ['LIVEKIT_URL', 'LIVEKIT_PUBLIC_URL', 'LIVEKIT_API_KEY', 'LIVEKIT_API_SECRET'].filter((name) => !env[name]);
    if (missing.length > 0) throw new Error(`Variables d'environnement manquantes pour le live : ${missing.join(', ')}`);
    return new LiveKitConfig(env.LIVEKIT_URL!, env.LIVEKIT_PUBLIC_URL!, env.LIVEKIT_API_KEY!, env.LIVEKIT_API_SECRET!);
  }
}
