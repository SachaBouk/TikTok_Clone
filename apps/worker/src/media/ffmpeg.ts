import { execFile } from 'node:child_process';
import { mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import type { Rendition } from './ladder';

export interface FfmpegOptions {
  ffmpegPath: string;
  ffprobePath: string;
  x264Preset: string;
  timeoutMs: number;
}

export interface MediaInfo {
  // Dimensions affichées : rotation des métadonnées déjà appliquée (vidéos d'iPhone).
  width: number;
  height: number;
  durationSeconds: number;
  hasAudio: boolean;
}

// Le fichier n'est pas une vidéo lisible : inutile de réessayer.
export class InvalidMediaError extends Error {
  constructor(detail: string) {
    super(`Fichier vidéo invalide : ${detail}`);
    this.name = 'InvalidMediaError';
  }
}

// Paramètres HLS (ADR-008). Segments de 4 s : démarrage rapide dans un feed en scroll continu.
// Image clé toutes les 2 s, à temps fixe : les segments sont alignés entre résolutions,
// ce qui permet à AVPlayer de changer de débit à chaque segment.
const SEGMENT_SECONDS = 4;
const KEYFRAME_INTERVAL_SECONDS = 2;
const AUDIO_KBPS = 128;
// Largeur visée pour la miniature (côté court), assez pour un écran d'iPhone en grille.
const THUMBNAIL_SHORT_SIDE = 720;

export async function probe(file: string, options: FfmpegOptions): Promise<MediaInfo> {
  let output: string;
  try {
    output = await run(options.ffprobePath, ['-v', 'error', '-show_streams', '-show_format', '-of', 'json', file], options.timeoutMs);
  } catch (error) {
    throw new InvalidMediaError((error as Error).message);
  }
  const { streams = [], format = {} } = JSON.parse(output) as FfprobeOutput;
  const video = streams.find((s) => s.codec_type === 'video' && s.disposition?.attached_pic !== 1);
  if (!video?.width || !video.height) throw new InvalidMediaError('aucune piste vidéo');

  const duration = Number(format.duration ?? video.duration);
  if (!(duration > 0)) throw new InvalidMediaError('durée inconnue');

  // Rotation : matrice d'affichage (FFmpeg récent) ou ancien tag `rotate`.
  const rotation = Number(video.side_data_list?.find((d) => d.rotation !== undefined)?.rotation ?? video.tags?.rotate ?? 0);
  const quarterTurn = Math.abs(rotation) % 180 === 90;
  return {
    width: quarterTurn ? video.height : video.width,
    height: quarterTurn ? video.width : video.height,
    durationSeconds: duration,
    hasAudio: streams.some((s) => s.codec_type === 'audio'),
  };
}

// Transcode en HLS multi-résolutions, en une seule passe de décodage :
// <outDir>/master.m3u8 et <outDir>/<résolution>/index.m3u8 + seg_000.ts…
export async function transcodeToHls(input: string, outDir: string, renditions: Rendition[], media: MediaInfo, options: FfmpegOptions) {
  await Promise.all(renditions.map((r) => mkdir(join(outDir, r.name), { recursive: true })));

  // La rotation est appliquée au décodage (autorotate, par défaut) : les dimensions sont celles affichées.
  const split = `[0:v]split=${renditions.length}${renditions.map((_, i) => `[s${i}]`).join('')}`;
  const scales = renditions.map((r, i) => `[s${i}]scale=${r.width}:${r.height},setsar=1[v${i}]`);
  const args = ['-nostdin', '-y', '-loglevel', 'error', '-i', input, '-filter_complex', [split, ...scales].join(';')];

  renditions.forEach((r, i) => {
    args.push('-map', `[v${i}]`);
    if (media.hasAudio) args.push('-map', '0:a:0');
    args.push(`-b:v:${i}`, `${r.videoKbps}k`, `-maxrate:v:${i}`, `${Math.round(r.videoKbps * 1.07)}k`, `-bufsize:v:${i}`, `${r.videoKbps * 1.5}k`);
  });

  args.push(
    '-c:v', 'libx264',
    '-preset', options.x264Preset,
    '-profile:v', 'high',
    // 8 bits 4:2:0 : lisible partout (les vidéos HDR 10 bits d'iPhone sont converties).
    '-pix_fmt', 'yuv420p',
    '-sc_threshold', '0',
    '-force_key_frames', `expr:gte(t,n_forced*${KEYFRAME_INTERVAL_SECONDS})`,
    '-map_metadata', '-1',
  );
  if (media.hasAudio) args.push('-c:a', 'aac', '-b:a', `${AUDIO_KBPS}k`, '-ac', '2', '-ar', '48000');

  const streamMap = renditions.map((r, i) => (media.hasAudio ? `v:${i},a:${i},name:${r.name}` : `v:${i},name:${r.name}`)).join(' ');
  args.push(
    '-f', 'hls',
    '-hls_time', String(SEGMENT_SECONDS),
    '-hls_playlist_type', 'vod',
    '-hls_flags', 'independent_segments',
    '-hls_segment_type', 'mpegts',
    '-hls_segment_filename', join(outDir, '%v', 'seg_%03d.ts'),
    '-master_pl_name', 'master.m3u8',
    '-var_stream_map', streamMap,
    join(outDir, '%v', 'index.m3u8'),
  );

  await run(options.ffmpegPath, args, options.timeoutMs);
}

// Miniature JPEG prise à 1 s (ou au milieu d'une vidéo plus courte), au format de la vidéo.
export async function createThumbnail(input: string, output: string, media: MediaInfo, options: FfmpegOptions) {
  const at = Math.min(1, media.durationSeconds / 2);
  const portrait = media.height >= media.width;
  const shortSide = Math.min(THUMBNAIL_SHORT_SIDE, media.width, media.height);
  // -2 : l'autre côté suit le format, arrondi à un nombre pair.
  const scale = portrait ? `scale=${shortSide}:-2` : `scale=-2:${shortSide}`;
  await run(
    options.ffmpegPath,
    ['-nostdin', '-y', '-loglevel', 'error', '-ss', String(at), '-i', input, '-frames:v', '1', '-vf', scale, '-q:v', '3', output],
    options.timeoutMs,
  );
}

function run(command: string, args: string[], timeoutMs: number): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile(command, args, { timeout: timeoutMs, maxBuffer: 64 * 1024 * 1024 }, (error, stdout, stderr) => {
      if (!error) return resolve(stdout);
      const reason = error.killed ? `délai de ${timeoutMs / 60_000} min dépassé` : stderr.trim().split('\n').slice(-3).join(' | ') || error.message;
      reject(new Error(`${command} a échoué : ${reason}`));
    });
  });
}

interface FfprobeOutput {
  streams?: {
    codec_type?: string;
    width?: number;
    height?: number;
    duration?: string;
    disposition?: { attached_pic?: number };
    tags?: { rotate?: string };
    side_data_list?: { rotation?: number }[];
  }[];
  format?: { duration?: string };
}
