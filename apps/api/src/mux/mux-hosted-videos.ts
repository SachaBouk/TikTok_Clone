import { Injectable } from '@nestjs/common';
import {
  type CreateHostedUpload,
  HOSTED_AUDIO_FILE,
  HOSTED_MP4_FILE,
  type HostedAsset,
  type HostedPlaybackPolicy,
  type HostedRendition,
  type HostedUpload,
  type HostedUploadState,
  HostedVideos,
  HostedVideosError,
} from './hosted-videos';
import { MuxConfig } from './mux.config';
import { signPlaybackToken, type PlaybackAudience } from './playback-token';

const STREAM_BASE = 'https://stream.mux.com';
const IMAGE_BASE = 'https://image.mux.com';

// API REST de Mux Video (v1), authentifiée par le jeton d'API (Basic). Réservée aux services par le port `HostedVideos`.
@Injectable()
export class MuxHostedVideos extends HostedVideos {
  constructor(
    private readonly config: MuxConfig,
    private readonly now: () => Date = () => new Date(),
  ) {
    super();
  }

  get uploadsEnabled(): boolean {
    return this.config.provider === 'mux' && this.config.apiConfigured;
  }

  async createUpload(input: CreateHostedUpload): Promise<HostedUpload> {
    const body = await this.request('POST', '/video/v1/uploads', {
      // L'app n'est pas un navigateur : aucune restriction d'origine utile.
      cors_origin: '*',
      timeout: input.timeoutSeconds,
      new_asset_settings: {
        passthrough: input.passthrough,
        playback_policies: [input.policy],
        video_quality: 'basic',
        max_resolution_tier: '1080p',
        ...(input.staticRenditions ? { static_renditions: [{ resolution: 'highest' }, { resolution: 'audio-only' }] } : {}),
      },
    });
    const data = record(record(body)?.data);
    const uploadId = text(data?.id);
    const url = text(data?.url);
    if (!uploadId || !url) throw new HostedVideosError(502, 'Mux : envoi direct sans identifiant ni URL');
    return { uploadId, url };
  }

  async getUpload(uploadId: string): Promise<HostedUploadState | null> {
    const body = await this.request('GET', `/video/v1/uploads/${encodeURIComponent(uploadId)}`, undefined, true);
    return body === null ? null : parseUpload(body);
  }

  async cancelUpload(uploadId: string): Promise<void> {
    try {
      await this.request('PUT', `/video/v1/uploads/${encodeURIComponent(uploadId)}/cancel`, undefined, true);
    } catch (error) {
      // Déjà terminé, annulé ou expiré : rien à annuler.
      if (!(error instanceof HostedVideosError) || error.status !== 400) throw error;
    }
  }

  async getAsset(assetId: string): Promise<HostedAsset | null> {
    const body = await this.request('GET', `/video/v1/assets/${encodeURIComponent(assetId)}`, undefined, true);
    return body === null ? null : parseAsset(body);
  }

  async deleteAsset(assetId: string): Promise<void> {
    await this.request('DELETE', `/video/v1/assets/${encodeURIComponent(assetId)}`, undefined, true);
  }

  async addPlaybackId(assetId: string, policy: HostedPlaybackPolicy): Promise<string> {
    const body = await this.request('POST', `/video/v1/assets/${encodeURIComponent(assetId)}/playback-ids`, { policy });
    const id = text(record(record(body)?.data)?.id);
    if (!id) throw new HostedVideosError(502, 'Mux : identifiant de lecture absent');
    return id;
  }

  async deletePlaybackId(assetId: string, playbackId: string): Promise<void> {
    await this.request('DELETE', `/video/v1/assets/${encodeURIComponent(assetId)}/playback-ids/${encodeURIComponent(playbackId)}`, undefined, true);
  }

  streamUrl(playbackId: string, signed: boolean): string {
    return this.withToken(`${STREAM_BASE}/${playbackId}.m3u8`, playbackId, 'v', signed);
  }

  thumbnailUrl(playbackId: string, signed: boolean): string {
    return this.withToken(`${IMAGE_BASE}/${playbackId}/thumbnail.jpg`, playbackId, 't', signed);
  }

  fileUrl(playbackId: string, name: string, signed: boolean): string {
    return this.withToken(`${STREAM_BASE}/${playbackId}/${name}`, playbackId, 'v', signed);
  }

  // Une URL signée ne porte que `token` : tout autre paramètre la rendrait invalide (documentation de Mux).
  private withToken(url: string, playbackId: string, audience: PlaybackAudience, signed: boolean): string {
    if (!signed) return url;
    const { signingKeyId, signingKey } = this.config;
    if (!signingKeyId || !signingKey) throw new HostedVideosError(503, 'Mux : clé de signature absente (MUX_SIGNING_KEY_ID, MUX_SIGNING_KEY)');
    return `${url}?token=${signPlaybackToken(playbackId, audience, signingKeyId, signingKey, this.now())}`;
  }

  // `nullOnNotFound` : 404 → null (envoi, asset ou identifiant de lecture inconnus).
  private async request(method: string, path: string, body?: unknown, nullOnNotFound = false): Promise<unknown> {
    const { tokenId, tokenSecret } = this.config;
    if (!tokenId || !tokenSecret) throw new HostedVideosError(503, 'Mux : jeton d’API absent (MUX_TOKEN_ID, MUX_TOKEN_SECRET)');
    const response = await fetch(`${this.config.apiUrl}${path}`, {
      method,
      headers: {
        Authorization: `Basic ${Buffer.from(`${tokenId}:${tokenSecret}`).toString('base64')}`,
        Accept: 'application/json',
        ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      signal: AbortSignal.timeout(10_000),
    });
    if (response.status === 404 && nullOnNotFound) return null;
    if (!response.ok) {
      const detail = await response.text().catch(() => '');
      throw new HostedVideosError(response.status, `Mux : HTTP ${response.status} sur ${method} ${path} ${detail.slice(0, 300)}`.trim());
    }
    return response.status === 204 ? {} : response.json();
  }
}

// Exportés pour les tests (forme des réponses de Mux).
export function parseUpload(body: unknown): HostedUploadState {
  const data = record(record(body)?.data);
  const status = text(data?.status);
  const assetId = text(data?.asset_id);
  if (status === 'asset_created' && assetId) return { status: 'assetCreated', assetId };
  if (status === 'waiting') return { status: 'waiting', assetId: null };
  // `errored`, `cancelled`, `timed_out`.
  return { status: 'failed', assetId };
}

export function parseAsset(body: unknown): HostedAsset {
  const data = record(record(body)?.data);
  const status = text(data?.status);
  const duration = data?.duration;
  const ids = data?.playback_ids;
  const playbackIds = (Array.isArray(ids) ? ids : []).flatMap((entry: unknown): HostedAsset['playbackIds'] => {
    const id = text(record(entry)?.id);
    const policy = text(record(entry)?.policy);
    return id && (policy === 'public' || policy === 'signed') ? [{ id, policy }] : [];
  });
  const files = record(data?.static_renditions)?.files;
  const renditions = (Array.isArray(files) ? files : []).flatMap((entry: unknown): HostedRendition[] => {
    const file = record(entry);
    const name = text(file?.name) ?? renditionName(text(file?.resolution));
    if (!name) return [];
    const size = Number(file?.filesize);
    const fileStatus = text(file?.status);
    return [
      {
        name,
        status: fileStatus === 'ready' ? 'ready' : fileStatus === 'errored' || fileStatus === 'skipped' ? 'failed' : 'preparing',
        size: Number.isFinite(size) && size > 0 ? size : null,
      },
    ];
  });
  return {
    status: status === 'ready' ? 'ready' : status === 'errored' ? 'errored' : 'preparing',
    durationSeconds: typeof duration === 'number' && duration > 0 ? duration : null,
    playbackIds,
    renditions,
  };
}

function renditionName(resolution: string | null): string | null {
  if (resolution === 'highest') return HOSTED_MP4_FILE;
  if (resolution === 'audio-only') return HOSTED_AUDIO_FILE;
  return null;
}

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === 'object' && value !== null && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
}

function text(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}
