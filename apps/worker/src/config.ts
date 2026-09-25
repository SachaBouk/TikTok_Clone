// Configuration du worker, lue depuis l'environnement (voir .env.example à la racine).
export interface WorkerConfig {
  redisUrl: string;
  ffmpegPath: string;
  ffprobePath: string;
  // Transcodages simultanés : un seul par défaut, FFmpeg occupe déjà tous les cœurs.
  concurrency: number;
  // Preset x264 : `veryfast` par défaut, compromis vitesse / qualité raisonnable pour un worker.
  x264Preset: string;
  // Durée maximale d'une commande FFmpeg, au-delà de laquelle elle est tuée (tentative en échec).
  ffmpegTimeoutMs: number;
  s3: {
    endpoint: string | undefined;
    region: string;
    accessKeyId: string;
    secretAccessKey: string;
    forcePathStyle: boolean;
    rawBucket: string;
    hlsBucket: string;
  };
  // Base publique des fichiers HLS : le CDN en production (ADR-008), le bucket HLS de MinIO en local.
  hlsPublicBaseUrl: string;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): WorkerConfig {
  const required = (name: string) => {
    const value = env[name];
    if (!value) throw new Error(`${name} manquant. Voir .env.example.`);
    return value;
  };
  return {
    redisUrl: required('REDIS_URL'),
    ffmpegPath: env.FFMPEG_PATH || 'ffmpeg',
    ffprobePath: env.FFPROBE_PATH || 'ffprobe',
    concurrency: Number(env.TRANSCODE_CONCURRENCY || 1),
    x264Preset: env.TRANSCODE_X264_PRESET || 'veryfast',
    ffmpegTimeoutMs: Number(env.TRANSCODE_TIMEOUT_MINUTES || 30) * 60_000,
    s3: {
      endpoint: env.S3_ENDPOINT || undefined,
      region: required('S3_REGION'),
      accessKeyId: required('S3_ACCESS_KEY'),
      secretAccessKey: required('S3_SECRET_KEY'),
      forcePathStyle: env.S3_FORCE_PATH_STYLE === 'true',
      rawBucket: required('S3_BUCKET_RAW'),
      hlsBucket: required('S3_BUCKET_HLS'),
    },
    hlsPublicBaseUrl: required('HLS_PUBLIC_BASE_URL').replace(/\/+$/, ''),
  };
}
