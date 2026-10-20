import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { TranscodeJobData } from '@repo/shared';
import type { WorkerConfig } from './config';
import { createThumbnail, extractSound, probe, transcodeToHls, type FfmpegOptions } from './media/ffmpeg';
import { renditionsFor } from './media/ladder';
import { assertPublishable } from './media/rules';
import type { VideoStorage } from './storage';

export interface TranscodeOutput {
  // URL du manifeste HLS maître, servi par le CDN (bucket HLS en local).
  hlsUrl: string;
  thumbnailUrl: string;
  // Son réutilisable (ADR-064) : vidéo avec du son, quand `extractSound` est demandé.
  soundUrl?: string;
  soundDurationSeconds?: number;
}

// Pipeline d'une vidéo (ADR-008) : téléchargement du brut, analyse (durée de 3 min au plus, ADR-040, ou 60 s pour une
// story, ADR-051 : `maxDurationSeconds`), HLS multi-résolutions,
// miniature, envoi au bucket HLS. Tout passe par un dossier temporaire, supprimé à la fin.
// Rejouable : une nouvelle tentative réécrit les mêmes clés sous `<videoId>/`.
// `toneMapping` : filtres présents dans FFmpeg (vérifié au démarrage, ADR-047). `extractSound` : piste son extraite en AAC
// (`sound.m4a`), réutilisable par les autres vidéos (ADR-064) ; vidéos seulement, pas les stories.
export async function transcode(
  job: TranscodeJobData,
  config: WorkerConfig,
  storage: VideoStorage,
  { toneMapping, maxDurationSeconds, extractSound: withSound = false }: { toneMapping: boolean; maxDurationSeconds: number; extractSound?: boolean },
): Promise<TranscodeOutput> {
  const options: FfmpegOptions = {
    ffmpegPath: config.ffmpegPath,
    ffprobePath: config.ffprobePath,
    x264Preset: config.x264Preset,
    timeoutMs: config.ffmpegTimeoutMs,
    toneMapping,
  };
  const workDir = await mkdtemp(join(tmpdir(), `transcode-${job.videoId}-`));
  try {
    const source = join(workDir, 'source');
    const output = join(workDir, 'hls');
    await storage.downloadRaw(job.rawKey, source);

    const media = await probe(source, options);
    // Durée maximale (ADR-040, ADR-051) : vérifiée avant tout transcodage.
    assertPublishable(media, maxDurationSeconds);
    await transcodeToHls(source, output, renditionsFor(media), media, options);
    await createThumbnail(source, join(output, 'thumbnail.jpg'), media, options);
    const sound = withSound && media.hasAudio;
    if (sound) await extractSound(source, join(output, 'sound.m4a'), options);
    await storage.uploadHls(output, job.videoId);

    const base = `${config.hlsPublicBaseUrl}/${job.videoId}`;
    return {
      hlsUrl: `${base}/master.m3u8`,
      thumbnailUrl: `${base}/thumbnail.jpg`,
      ...(sound ? { soundUrl: `${base}/sound.m4a`, soundDurationSeconds: media.durationSeconds } : {}),
    };
  } finally {
    await rm(workDir, { recursive: true, force: true });
  }
}
