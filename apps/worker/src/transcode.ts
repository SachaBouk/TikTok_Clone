import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { TranscodeJobData } from '@repo/shared';
import type { WorkerConfig } from './config';
import { createThumbnail, probe, transcodeToHls, type FfmpegOptions } from './media/ffmpeg';
import { renditionsFor } from './media/ladder';
import type { VideoStorage } from './storage';

export interface TranscodeOutput {
  // URL du manifeste HLS maître, servi par le CDN (bucket HLS en local).
  hlsUrl: string;
  thumbnailUrl: string;
}

// Pipeline d'une vidéo (ADR-008) : téléchargement du brut, analyse, HLS multi-résolutions,
// miniature, envoi au bucket HLS. Tout passe par un dossier temporaire, supprimé à la fin.
// Rejouable : une nouvelle tentative réécrit les mêmes clés sous `<videoId>/`.
export async function transcode(job: TranscodeJobData, config: WorkerConfig, storage: VideoStorage): Promise<TranscodeOutput> {
  const options: FfmpegOptions = {
    ffmpegPath: config.ffmpegPath,
    ffprobePath: config.ffprobePath,
    x264Preset: config.x264Preset,
    timeoutMs: config.ffmpegTimeoutMs,
  };
  const workDir = await mkdtemp(join(tmpdir(), `transcode-${job.videoId}-`));
  try {
    const source = join(workDir, 'source');
    const output = join(workDir, 'hls');
    await storage.downloadRaw(job.rawKey, source);

    const media = await probe(source, options);
    await transcodeToHls(source, output, renditionsFor(media), media, options);
    await createThumbnail(source, join(output, 'thumbnail.jpg'), media, options);
    await storage.uploadHls(output, job.videoId);

    const base = `${config.hlsPublicBaseUrl}/${job.videoId}`;
    return { hlsUrl: `${base}/master.m3u8`, thumbnailUrl: `${base}/thumbnail.jpg` };
  } finally {
    await rm(workDir, { recursive: true, force: true });
  }
}
