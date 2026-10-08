// Configuration du stockage objet compatible S3 (ADR-015), lue depuis l'environnement (voir .env.example).
// Partagée par les modules qui stockent des fichiers (`videos`, `users`, `stories`) ; seuls leurs adaptateurs
// `infrastructure/` l'utilisent (ADR-003).
export class StorageConfig {
  constructor(
    // Absent pour AWS S3 (point de terminaison par défaut de la région).
    readonly endpoint: string | undefined,
    // Hôte utilisé dans les URLs signées données à l'app. La signature couvre l'hôte : il doit être
    // celui que l'app joint (ex. l'IP du Mac sur le réseau local pour un iPhone physique).
    readonly publicEndpoint: string | undefined,
    readonly region: string,
    readonly accessKeyId: string,
    readonly secretAccessKey: string,
    readonly forcePathStyle: boolean,
    readonly rawBucket: string,
    // Fichiers HLS et miniatures, écrits par le worker ; l'API y supprime (vidéo ou story supprimée) et y reçoit les
    // photos des stories (ADR-051), servies sous `hlsPublicBaseUrl` (le CDN en production).
    readonly hlsBucket: string,
    readonly hlsPublicBaseUrl: string,
    // Photos de profil : bucket en lecture anonyme (le CDN en production), servi sous `avatarsPublicBaseUrl`.
    readonly avatarsBucket: string,
    readonly avatarsPublicBaseUrl: string,
  ) {}

  static fromEnv(env: NodeJS.ProcessEnv = process.env): StorageConfig {
    const required = (name: string) => {
      const value = env[name];
      if (!value) throw new Error(`${name} manquant. Voir .env.example.`);
      return value;
    };
    const endpoint = env.S3_ENDPOINT || undefined;
    return new StorageConfig(
      endpoint,
      env.S3_PUBLIC_ENDPOINT || endpoint,
      required('S3_REGION'),
      required('S3_ACCESS_KEY'),
      required('S3_SECRET_KEY'),
      env.S3_FORCE_PATH_STYLE === 'true',
      required('S3_BUCKET_RAW'),
      required('S3_BUCKET_HLS'),
      required('HLS_PUBLIC_BASE_URL').replace(/\/+$/, ''),
      required('S3_BUCKET_AVATARS'),
      required('AVATARS_PUBLIC_BASE_URL').replace(/\/+$/, ''),
    );
  }
}
