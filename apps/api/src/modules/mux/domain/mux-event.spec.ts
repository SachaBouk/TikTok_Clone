import { describe, expect, it } from 'vitest';
import { MalformedMuxEventError, parseMuxEvent } from './mux-event';

const VIDEO = '019a4f7e-1c2d-7a3b-8c4d-5e6f7a8b9c0d';

describe('parseMuxEvent', () => {
  it('lit la vidéo ou la story d’un asset par son passthrough', () => {
    expect(
      parseMuxEvent({
        type: 'video.asset.ready',
        object: { type: 'asset', id: 'a1' },
        data: { id: 'a1', upload_id: 'u1', passthrough: `video:${VIDEO}` },
      }),
    ).toEqual({ type: 'video.asset.ready', kind: 'video', id: VIDEO, uploadId: 'u1', assetId: 'a1' });
    expect(
      parseMuxEvent({ type: 'video.asset.errored', object: { type: 'asset', id: 'a2' }, data: { passthrough: `story:${VIDEO}` } }),
    ).toMatchObject({
      kind: 'story',
      assetId: 'a2',
    });
  });

  it('lit l’envoi direct et l’asset créé ; une version statique par son asset seulement', () => {
    expect(
      parseMuxEvent({
        type: 'video.upload.asset_created',
        object: { type: 'upload', id: 'u1' },
        data: { id: 'u1', asset_id: 'a1', new_asset_settings: { passthrough: `video:${VIDEO}` } },
      }),
    ).toMatchObject({ kind: 'video', uploadId: 'u1', assetId: 'a1' });
    expect(parseMuxEvent({ type: 'video.asset.static_rendition.ready', data: { id: 'r1', asset_id: 'a1', name: 'audio.m4a' } })).toEqual({
      type: 'video.asset.static_rendition.ready',
      kind: null,
      id: null,
      uploadId: null,
      assetId: 'a1',
    });
  });

  it('ignore les autres événements, refuse un corps sans type', () => {
    expect(parseMuxEvent({ type: 'video.live_stream.active', data: {} })).toBeNull();
    expect(() => parseMuxEvent({ data: {} })).toThrow(MalformedMuxEventError);
  });
});
