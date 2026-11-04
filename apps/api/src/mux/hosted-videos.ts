// Port de l'hébergement des vidéos chez Mux (ADR-074), partagé par les modules `videos` et `stories` : envoi direct par
// l'app, encodage, lecture (publique ou signée) et versions statiques. Sans NestJS ni HTTP : les services le reçoivent par
// leur factory, et les tests utilisent l'adaptateur en mémoire.

export type HostedPlaybackPolicy = 'public' | 'signed';

// Versions statiques demandées pour une vidéo (pas pour une story) : MP4 de téléchargement (ADR-067) et son seul (ADR-064).
export const HOSTED_MP4_FILE = 'highest.mp4';
export const HOSTED_AUDIO_FILE = 'audio.m4a';

export interface CreateHostedUpload {
  // Relie l'asset à la vidéo ou à la story (`video:<id>`, `story:<id>`), relu dans les webhooks.
  passthrough: string;
  policy: HostedPlaybackPolicy;
  // Versions statiques (MP4 et son) : vidéos seulement.
  staticRenditions: boolean;
  // Délai pour envoyer le fichier, aligné sur la validité des URLs du pipeline maison (ADR-007).
  timeoutSeconds: number;
}

export interface HostedUpload {
  uploadId: string;
  // URL d'envoi direct (PUT par morceaux, `Content-Range`).
  url: string;
}

// État d'un envoi direct : en attente du fichier, asset créé, ou perdu (erreur, annulé, délai dépassé).
export interface HostedUploadState {
  status: 'waiting' | 'assetCreated' | 'failed';
  assetId: string | null;
}

export interface HostedRendition {
  name: string;
  status: 'preparing' | 'ready' | 'failed';
  // Taille en octets, connue une fois prête.
  size: number | null;
}

export interface HostedAsset {
  status: 'preparing' | 'ready' | 'errored';
  durationSeconds: number | null;
  playbackIds: { id: string; policy: HostedPlaybackPolicy }[];
  renditions: HostedRendition[];
}

export abstract class HostedVideos {
  // Nouveaux envois chez Mux (`VIDEO_PROVIDER=mux`) ; faux : pipeline maison. Les vidéos déjà chez Mux restent gérées.
  abstract readonly uploadsEnabled: boolean;
  // Lève une erreur si Mux refuse (plan gratuit plein, Mux injoignable) : l'appelant bascule sur le pipeline maison.
  abstract createUpload(input: CreateHostedUpload): Promise<HostedUpload>;
  // Null : envoi inconnu de Mux.
  abstract getUpload(uploadId: string): Promise<HostedUploadState | null>;
  abstract cancelUpload(uploadId: string): Promise<void>;
  // Null : asset inconnu (supprimé).
  abstract getAsset(assetId: string): Promise<HostedAsset | null>;
  // Sans effet si l'asset n'existe plus.
  abstract deleteAsset(assetId: string): Promise<void>;
  abstract addPlaybackId(assetId: string, policy: HostedPlaybackPolicy): Promise<string>;
  abstract deletePlaybackId(assetId: string, playbackId: string): Promise<void>;
  // URLs de lecture ; `signed` : avec un jeton (identifiant de lecture signé, vidéo privée, ADR-061).
  abstract streamUrl(playbackId: string, signed: boolean): string;
  abstract thumbnailUrl(playbackId: string, signed: boolean): string;
  abstract fileUrl(playbackId: string, name: string, signed: boolean): string;
}

// Erreur de l'API de Mux (statut HTTP, message).
export class HostedVideosError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}
