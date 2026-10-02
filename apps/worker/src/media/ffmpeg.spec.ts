// Test d'intégration avec le vrai FFmpeg (requis par le worker, voir README).
import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createThumbnail, InvalidMediaError, probe, transcodeToHls, type FfmpegOptions } from './ffmpeg';
import { renditionsFor } from './ladder';

const options: FfmpegOptions = { ffmpegPath: 'ffmpeg', ffprobePath: 'ffprobe', x264Preset: 'ultrafast', timeoutMs: 60_000 };
const ffmpeg = (...args: string[]) => execFileSync('ffmpeg', ['-nostdin', '-y', '-loglevel', 'error', ...args]);
const ffprobeJson = (file: string) =>
  JSON.parse(execFileSync('ffprobe', ['-v', 'error', '-show_streams', '-of', 'json', file]).toString()) as {
    streams: { codec_type: string; width?: number; height?: number; side_data_list?: unknown[] }[];
  };

let dir: string;
// Comme un iPhone : image enregistrée en 1280×720 avec une rotation de 90° dans les métadonnées → affichée en 720×1280.
let iphoneLike: string;
let landscapeNoAudio: string;
let corrupted: string;

beforeAll(() => {
  dir = mkdtempSync(join(tmpdir(), 'ffmpeg-spec-'));
  const raw = join(dir, 'raw.mp4');
  ffmpeg(
    '-f',
    'lavfi',
    '-i',
    'testsrc2=size=1280x720:rate=30',
    '-f',
    'lavfi',
    '-i',
    'sine=frequency=440',
    '-t',
    '5',
    '-c:v',
    'libx264',
    '-preset',
    'ultrafast',
    '-c:a',
    'aac',
    '-shortest',
    raw,
  );
  iphoneLike = join(dir, 'iphone.mov');
  ffmpeg('-display_rotation:v:0', '90', '-i', raw, '-c', 'copy', iphoneLike);
  landscapeNoAudio = join(dir, 'landscape.mp4');
  ffmpeg('-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=30', '-t', '3', '-c:v', 'libx264', '-preset', 'ultrafast', landscapeNoAudio);
  corrupted = join(dir, 'corrupted.mp4');
  writeFileSync(corrupted, Buffer.alloc(4096, 42));
});

afterAll(() => rmSync(dir, { recursive: true, force: true }));

describe('probe', () => {
  it("applique la rotation des métadonnées (vidéo d'iPhone) et détecte le son", async () => {
    const info = await probe(iphoneLike, options);
    expect(info).toMatchObject({ width: 720, height: 1280, hasAudio: true });
    expect(info.durationSeconds).toBeCloseTo(5, 0);
  });

  it('détecte une vidéo sans piste audio', async () => {
    await expect(probe(landscapeNoAudio, options)).resolves.toMatchObject({ width: 640, height: 360, hasAudio: false });
  });

  it('rejette un fichier qui n’est pas une vidéo', async () => {
    await expect(probe(corrupted, options)).rejects.toBeInstanceOf(InvalidMediaError);
  });
});

describe('transcodeToHls', () => {
  it('produit un master HLS multi-résolutions, en vertical, avec segments alignés', async () => {
    const out = join(dir, 'hls-iphone');
    const media = await probe(iphoneLike, options);
    await transcodeToHls(iphoneLike, out, renditionsFor(media), media, options);

    const master = readFileSync(join(out, 'master.m3u8'), 'utf8');
    expect(master.match(/RESOLUTION=\d+x\d+/g)).toEqual(['RESOLUTION=360x640', 'RESOLUTION=720x1280']);
    expect(master).toMatch(/CODECS="avc1\.[0-9a-f]+,mp4a\.40\.2"/);
    expect(master).toContain('360p/index.m3u8');
    expect(master).toContain('720p/index.m3u8');

    const playlists = ['360p', '720p'].map((name) => readFileSync(join(out, name, 'index.m3u8'), 'utf8'));
    for (const playlist of playlists) {
      expect(playlist).toContain('#EXT-X-PLAYLIST-TYPE:VOD');
      expect(playlist).toContain('#EXT-X-ENDLIST');
    }
    // Mêmes durées de segments dans chaque résolution : AVPlayer peut changer de débit à chaque segment.
    const durations = playlists.map((p) => p.match(/#EXTINF:[\d.]+/g));
    expect(durations[0]).toEqual(durations[1]);
    expect(durations[0]!.length).toBe(2); // 5 s en segments de 4 s

    const segment = ffprobeJson(join(out, '720p', 'seg_000.ts'));
    const video = segment.streams.find((s) => s.codec_type === 'video')!;
    expect(`${video.width}x${video.height}`).toBe('720x1280');
    expect(video.side_data_list ?? []).toEqual([]); // rotation appliquée à l'image, plus dans les métadonnées
    expect(segment.streams.some((s) => s.codec_type === 'audio')).toBe(true);
  });

  it('gère une vidéo sans son', async () => {
    const out = join(dir, 'hls-landscape');
    const media = await probe(landscapeNoAudio, options);
    await transcodeToHls(landscapeNoAudio, out, renditionsFor(media), media, options);

    const master = readFileSync(join(out, 'master.m3u8'), 'utf8');
    expect(master.match(/RESOLUTION=\d+x\d+/g)).toEqual(['RESOLUTION=640x360']);
    expect(master).not.toContain('mp4a');
    expect(readdirSync(join(out, '360p')).filter((f) => f.endsWith('.ts')).length).toBeGreaterThan(0);
  });
});

describe('createThumbnail', () => {
  it('crée un JPEG au format de la vidéo affichée', async () => {
    const output = join(dir, 'thumbnail.jpg');
    await createThumbnail(iphoneLike, output, await probe(iphoneLike, options), options);

    expect(existsSync(output)).toBe(true);
    expect(readFileSync(output).subarray(0, 2).toString('hex')).toBe('ffd8'); // signature JPEG
    const image = ffprobeJson(output).streams[0];
    expect(`${image.width}x${image.height}`).toBe('720x1280');
  });
});

// La position GPS d'un fichier brut (métadonnées QuickTime d'iPhone) ne doit se retrouver dans aucun fichier publié.
// L'app la retire avant l'envoi (brut propre) ; ce test vérifie le reste de la chaîne. Constaté avec FFmpeg 8 :
// ni les segments HLS (MPEG-TS ou fMP4) ni la miniature JPEG ne reprennent ces balises, même sans `-map_metadata -1`.
describe('métadonnées personnelles', () => {
  it('aucune position dans le HLS ni dans la miniature', async () => {
    const located = join(dir, 'located.mov');
    ffmpeg(
      '-i',
      iphoneLike,
      '-c',
      'copy',
      '-movflags',
      'use_metadata_tags',
      '-metadata',
      'com.apple.quicktime.location.ISO6709=+48.8566+002.3522+035.000/',
      '-metadata',
      'location=+48.8566+002.3522/',
      located,
    );
    expect(readFileSync(located).includes('+48.8566')).toBe(true);

    const out = join(dir, 'hls-located');
    const media = await probe(located, options);
    await transcodeToHls(located, out, renditionsFor(media), media, options);
    await createThumbnail(located, join(out, 'thumbnail.jpg'), media, options);

    const published = readdirSync(out, { recursive: true, withFileTypes: true }).filter((entry) => entry.isFile());
    expect(published.length).toBeGreaterThan(3);
    for (const entry of published) {
      const content = readFileSync(join(entry.parentPath, entry.name));
      expect(content.includes('48.8566'), entry.name).toBe(false);
      expect(content.includes('ISO6709'), entry.name).toBe(false);
    }
  });
});
