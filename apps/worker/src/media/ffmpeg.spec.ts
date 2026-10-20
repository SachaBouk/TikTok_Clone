// Test d'intégration avec le vrai FFmpeg (requis par le worker, voir README).
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import {
  createCoverThumbnail,
  createThumbnail,
  extractSound,
  InvalidMediaError,
  probe,
  supportsToneMapping,
  transcodeToHls,
  type FfmpegOptions,
} from './ffmpeg';
import { renditionsFor } from './ladder';

const options: FfmpegOptions = { ffmpegPath: 'ffmpeg', ffprobePath: 'ffprobe', x264Preset: 'ultrafast', timeoutMs: 60_000, toneMapping: true };
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
// HDR (ADR-047) : la même mire SDR, convertie en BT.2020 10 bits, blanc à 203 nits (BT.2408, comme un iPhone), en PQ et en
// HLG. Un bon tone mapping doit rendre des couleurs proches de la mire d'origine.
let sdrReference: string;
let pq: string;
let hlg: string;

// Écart (PSNR moyen, en dB) entre deux images ou vidéos de même taille, comparées image par image.
function psnr(a: string, b: string): number {
  const { stderr } = spawnSync(
    'ffmpeg',
    ['-nostdin', '-i', a, '-i', b, '-lavfi', '[0:v]format=rgb24[a];[1:v]format=rgb24[b];[a][b]psnr', '-f', 'null', '-'],
    {
      encoding: 'utf8',
    },
  );
  return Number(/average:([\d.]+)/.exec(stderr)?.[1]);
}

function toHdr(source: string, transfer: string, output: string) {
  ffmpeg(
    '-i',
    source,
    '-vf',
    `zscale=tin=bt709:min=bt709:pin=bt709:rin=tv:t=linear:p=bt709,format=gbrpf32le,zscale=p=bt2020:t=${transfer}:m=bt2020nc:r=tv:npl=203,format=yuv420p10le`,
    '-c:v',
    'libx264',
    '-preset',
    'ultrafast',
    '-qp',
    '0',
    '-color_primaries',
    'bt2020',
    '-color_trc',
    transfer,
    '-colorspace',
    'bt2020nc',
    output,
  );
}

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

  sdrReference = join(dir, 'sdr.mp4');
  ffmpeg(
    '-f',
    'lavfi',
    '-i',
    'testsrc2=size=360x640:rate=30',
    '-t',
    '2',
    '-c:v',
    'libx264',
    '-preset',
    'ultrafast',
    '-qp',
    '0',
    '-color_trc',
    'bt709',
    sdrReference,
  );
  pq = join(dir, 'pq.mp4');
  toHdr(sdrReference, 'smpte2084', pq);
  hlg = join(dir, 'hlg.mp4');
  toHdr(sdrReference, 'arib-std-b67', hlg);
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

  it('détecte une vidéo HDR (PQ ou HLG) ; une vidéo SDR ne l’est pas (ADR-047)', async () => {
    await expect(probe(pq, options)).resolves.toMatchObject({ width: 360, height: 640, hdr: true });
    await expect(probe(hlg, options)).resolves.toMatchObject({ hdr: true });
    await expect(probe(iphoneLike, options)).resolves.toMatchObject({ hdr: false });
  });
});

describe('tone mapping HDR (ADR-047)', () => {
  it('le FFmpeg des tests a les filtres zscale et tonemap ; un FFmpeg introuvable non', async () => {
    await expect(supportsToneMapping('ffmpeg')).resolves.toBe(true);
    await expect(supportsToneMapping(join(dir, 'introuvable'))).resolves.toBe(false);
  });

  it.each([
    ['PQ', () => pq],
    ['HLG', () => hlg],
  ])('%s : HLS et miniature en SDR BT.709 8 bits, aux couleurs de la source', async (_, source) => {
    const out = join(dir, `hls-${_}`);
    const media = await probe(source(), options);
    await transcodeToHls(source(), out, renditionsFor(media), media, options);
    await createThumbnail(source(), join(out, 'thumbnail.jpg'), media, options);

    const rendition = join(out, '360p', 'index.m3u8');
    const probed = execFileSync('ffprobe', [
      '-v',
      'error',
      '-select_streams',
      'v:0',
      '-show_entries',
      'stream=pix_fmt,color_primaries,color_transfer,color_space',
      '-of',
      'json',
      rendition,
    ]).toString();
    const [video] = (JSON.parse(probed) as { streams: Record<string, string>[] }).streams;
    expect(video).toMatchObject({ pix_fmt: 'yuv420p', color_primaries: 'bt709', color_transfer: 'bt709', color_space: 'bt709' });
    // Proche de la mire SDR d'origine (sans tone mapping : environ 8 à 10 dB, couleurs délavées).
    expect(psnr(rendition, sdrReference)).toBeGreaterThan(18);
    const reference = join(dir, `reference-${_}.png`);
    ffmpeg('-ss', '1', '-i', sdrReference, '-frames:v', '1', reference);
    expect(psnr(join(out, 'thumbnail.jpg'), reference)).toBeGreaterThan(18);
  });

  it('sans les filtres : conversion d’avant, couleurs délavées', async () => {
    const out = join(dir, 'hls-sans-tonemap');
    const withoutToneMapping = { ...options, toneMapping: false };
    const media = await probe(pq, withoutToneMapping);
    await transcodeToHls(pq, out, renditionsFor(media), media, withoutToneMapping);
    expect(psnr(join(out, '360p', 'index.m3u8'), sdrReference)).toBeLessThan(12);
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

describe('extractSound (ADR-064)', () => {
  it('extrait la piste son seule, en AAC stéréo, sans position', async () => {
    const located = join(dir, 'located-sound.mov');
    ffmpeg('-i', iphoneLike, '-c', 'copy', '-movflags', 'use_metadata_tags', '-metadata', 'location=+48.8566+002.3522/', located);
    const output = join(dir, 'sound.m4a');
    await extractSound(located, output, options);

    const streams = (
      JSON.parse(execFileSync('ffprobe', ['-v', 'error', '-show_streams', '-of', 'json', output]).toString()) as {
        streams: { codec_type: string; codec_name: string; channels?: number }[];
      }
    ).streams;
    expect(streams.map((stream) => stream.codec_type)).toEqual(['audio']);
    expect(streams[0].codec_name).toBe('aac');
    expect(streams[0].channels).toBe(2);
    expect(readFileSync(output).includes('48.8566')).toBe(false);
  });
});

describe('createCoverThumbnail (ADR-065)', () => {
  it('réencode la couverture au petit côté des miniatures, sans métadonnées', async () => {
    const cover = join(dir, 'cover.jpg');
    ffmpeg('-f', 'lavfi', '-i', 'color=c=red:s=1080x1920', '-frames:v', '1', '-metadata', 'comment=48.8566', cover);
    const output = join(dir, 'cover-thumbnail.jpg');
    await createCoverThumbnail(cover, output, options);
    const [stream] = (
      JSON.parse(execFileSync('ffprobe', ['-v', 'error', '-show_streams', '-of', 'json', output]).toString()) as {
        streams: { width: number; height: number }[];
      }
    ).streams;
    expect([stream.width, stream.height]).toEqual([720, 1280]);
    expect(readFileSync(output).includes('48.8566')).toBe(false);
  });

  it('refuse un fichier qui n’est pas une image', async () => {
    const notImage = join(dir, 'not-image.jpg');
    writeFileSync(notImage, 'pas une image');
    await expect(createCoverThumbnail(notImage, join(dir, 'never.jpg'), options)).rejects.toThrow();
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
