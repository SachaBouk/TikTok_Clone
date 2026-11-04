import {
  type CreateHostedUpload,
  HOSTED_AUDIO_FILE,
  HOSTED_MP4_FILE,
  type HostedAsset,
  type HostedPlaybackPolicy,
  type HostedUpload,
  type HostedUploadState,
  HostedVideos,
  HostedVideosError,
} from './hosted-videos';

interface StoredUpload {
  input: CreateHostedUpload;
  state: HostedUploadState;
}

// Mux en mémoire, pour les tests des services : URLs `https://mux.test/…`, jeton `token-<id>-<usage>`. Les aides `finish`,
// `makeReady`… jouent le rôle de l'app (envoi terminé) et de Mux (encodage).
export class InMemoryHostedVideos extends HostedVideos {
  readonly uploads = new Map<string, StoredUpload>();
  readonly assets = new Map<string, HostedAsset & { passthrough: string }>();
  readonly deletedAssets: string[] = [];
  readonly cancelledUploads: string[] = [];
  // Prochaine création refusée (plan gratuit plein, Mux injoignable).
  failNextCreate = false;
  private sequence = 0;

  constructor(public uploadsEnabled = true) {
    super();
  }

  createUpload(input: CreateHostedUpload): Promise<HostedUpload> {
    if (this.failNextCreate) {
      this.failNextCreate = false;
      return Promise.reject(new HostedVideosError(400, 'limite du plan atteinte'));
    }
    const uploadId = this.nextId('upload');
    this.uploads.set(uploadId, { input, state: { status: 'waiting', assetId: null } });
    return Promise.resolve({ uploadId, url: `https://mux.test/upload/${uploadId}` });
  }

  getUpload(uploadId: string): Promise<HostedUploadState | null> {
    return Promise.resolve(this.uploads.get(uploadId)?.state ?? null);
  }

  cancelUpload(uploadId: string): Promise<void> {
    const upload = this.uploads.get(uploadId);
    if (upload?.state.status === 'waiting') upload.state = { status: 'failed', assetId: null };
    this.cancelledUploads.push(uploadId);
    return Promise.resolve();
  }

  getAsset(assetId: string): Promise<HostedAsset | null> {
    const asset = this.assets.get(assetId);
    return Promise.resolve(asset ? structuredClone(asset) : null);
  }

  deleteAsset(assetId: string): Promise<void> {
    this.assets.delete(assetId);
    this.deletedAssets.push(assetId);
    return Promise.resolve();
  }

  addPlaybackId(assetId: string, policy: HostedPlaybackPolicy): Promise<string> {
    const asset = this.assets.get(assetId);
    if (!asset) return Promise.reject(new HostedVideosError(404, 'asset inconnu'));
    const id = this.nextId('playback');
    asset.playbackIds.push({ id, policy });
    return Promise.resolve(id);
  }

  deletePlaybackId(assetId: string, playbackId: string): Promise<void> {
    const asset = this.assets.get(assetId);
    if (asset) asset.playbackIds = asset.playbackIds.filter((entry) => entry.id !== playbackId);
    return Promise.resolve();
  }

  streamUrl(playbackId: string, signed: boolean): string {
    return `https://mux.test/${playbackId}.m3u8${signed ? `?token=token-${playbackId}-v` : ''}`;
  }

  thumbnailUrl(playbackId: string, signed: boolean): string {
    return `https://mux.test/${playbackId}/thumbnail.jpg${signed ? `?token=token-${playbackId}-t` : ''}`;
  }

  fileUrl(playbackId: string, name: string, signed: boolean): string {
    return `https://mux.test/${playbackId}/${name}${signed ? `?token=token-${playbackId}-v` : ''}`;
  }

  // L'app a envoyé tout le fichier : Mux crée l'asset (en préparation), avec l'identifiant de lecture demandé.
  finish(uploadId: string): string {
    const upload = this.uploads.get(uploadId);
    if (!upload) throw new Error(`envoi inconnu : ${uploadId}`);
    const assetId = this.nextId('asset');
    upload.state = { status: 'assetCreated', assetId };
    this.assets.set(assetId, {
      passthrough: upload.input.passthrough,
      status: 'preparing',
      durationSeconds: null,
      playbackIds: [{ id: this.nextId('playback'), policy: upload.input.policy }],
      renditions: upload.input.staticRenditions
        ? [
            { name: HOSTED_MP4_FILE, status: 'preparing', size: null },
            { name: HOSTED_AUDIO_FILE, status: 'preparing', size: null },
          ]
        : [],
    });
    return assetId;
  }

  // Mux a encodé l'asset ; `files` : versions statiques prêtes (taille en octets).
  makeReady(assetId: string, durationSeconds: number, files: Record<string, number> = {}): void {
    const asset = this.asset(assetId);
    asset.status = 'ready';
    asset.durationSeconds = durationSeconds;
    asset.renditions = asset.renditions.map((rendition) =>
      files[rendition.name] ? { ...rendition, status: 'ready', size: files[rendition.name] } : rendition,
    );
  }

  makeErrored(assetId: string): void {
    this.asset(assetId).status = 'errored';
  }

  assetOfUpload(uploadId: string): string | null {
    return this.uploads.get(uploadId)?.state.assetId ?? null;
  }

  private asset(assetId: string): HostedAsset & { passthrough: string } {
    const asset = this.assets.get(assetId);
    if (!asset) throw new Error(`asset inconnu : ${assetId}`);
    return asset;
  }

  private nextId(prefix: string): string {
    this.sequence += 1;
    return `${prefix}-${this.sequence}`;
  }
}
