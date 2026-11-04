import { generateKeyPairSync } from 'node:crypto';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { MuxConfig } from './mux.config';
import { MuxHostedVideos, parseAsset, parseUpload } from './mux-hosted-videos';

const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const config = new MuxConfig('mux', 'https://mux.example', 'id', 'secret', 'webhook', 'key-1', privateKey);

describe('MuxHostedVideos', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('crée un envoi direct : politique de lecture, versions statiques, passthrough, authentification Basic', async () => {
    const fetchMock = vi.fn(() => Promise.resolve(Response.json({ data: { id: 'up-1', url: 'https://storage.example/up-1' } }, { status: 201 })));
    vi.stubGlobal('fetch', fetchMock);
    const upload = await new MuxHostedVideos(config).createUpload({
      passthrough: 'video:v1',
      policy: 'signed',
      staticRenditions: true,
      timeoutSeconds: 7200,
    });

    expect(upload).toEqual({ uploadId: 'up-1', url: 'https://storage.example/up-1' });
    const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe('https://mux.example/video/v1/uploads');
    expect((init.headers as Record<string, string>).Authorization).toBe(`Basic ${Buffer.from('id:secret').toString('base64')}`);
    expect(JSON.parse(init.body as string)).toEqual({
      cors_origin: '*',
      timeout: 7200,
      new_asset_settings: {
        passthrough: 'video:v1',
        playback_policies: ['signed'],
        video_quality: 'basic',
        max_resolution_tier: '1080p',
        static_renditions: [{ resolution: 'highest' }, { resolution: 'audio-only' }],
      },
    });
  });

  it('lève une erreur si Mux refuse, null pour un asset inconnu', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(() => Promise.resolve(new Response('limite', { status: 403 }))),
    );
    const mux = new MuxHostedVideos(config);
    await expect(mux.createUpload({ passthrough: 'video:v1', policy: 'public', staticRenditions: false, timeoutSeconds: 60 })).rejects.toThrow(/403/);
    vi.stubGlobal(
      'fetch',
      vi.fn(() => Promise.resolve(new Response('', { status: 404 }))),
    );
    expect(await mux.getAsset('inconnu')).toBeNull();
  });

  it('URLs de lecture : sans jeton pour une vidéo publique, avec le seul paramètre `token` sinon', () => {
    const mux = new MuxHostedVideos(config, () => new Date('2026-11-04T10:00:00Z'));
    expect(mux.streamUrl('pb', false)).toBe('https://stream.mux.com/pb.m3u8');
    expect(mux.thumbnailUrl('pb', false)).toBe('https://image.mux.com/pb/thumbnail.jpg');
    expect(mux.fileUrl('pb', 'highest.mp4', false)).toBe('https://stream.mux.com/pb/highest.mp4');
    expect(mux.streamUrl('pb', true)).toMatch(/^https:\/\/stream\.mux\.com\/pb\.m3u8\?token=[\w-]+\.[\w-]+\.[\w-]+$/);
  });

  it('lit l’état d’un envoi direct et d’un asset (versions statiques comprises)', () => {
    expect(parseUpload({ data: { status: 'asset_created', asset_id: 'a1' } })).toEqual({ status: 'assetCreated', assetId: 'a1' });
    expect(parseUpload({ data: { status: 'waiting' } })).toEqual({ status: 'waiting', assetId: null });
    expect(parseUpload({ data: { status: 'timed_out' } })).toEqual({ status: 'failed', assetId: null });

    const asset = parseAsset({
      data: {
        status: 'ready',
        duration: 12.4,
        playback_ids: [
          { id: 'pb', policy: 'public' },
          { id: 'drm', policy: 'drm' },
        ],
        static_renditions: {
          files: [
            { name: 'highest.mp4', status: 'ready', filesize: '5000000', resolution: 'highest' },
            { resolution: 'audio-only', status: 'skipped' },
          ],
        },
      },
    });
    expect(asset).toEqual({
      status: 'ready',
      durationSeconds: 12.4,
      playbackIds: [{ id: 'pb', policy: 'public' }],
      renditions: [
        { name: 'highest.mp4', status: 'ready', size: 5_000_000 },
        { name: 'audio.m4a', status: 'failed', size: null },
      ],
    });
  });
});
