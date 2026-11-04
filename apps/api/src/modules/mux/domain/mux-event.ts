// Événement du webhook de Mux (ADR-074), réduit à ce qui permet de retrouver la vidéo ou la story : l'état lui-même est
// toujours relu chez Mux (idempotent, insensible à l'ordre et aux doublons).

export interface MuxEvent {
  type: string;
  // `passthrough` de l'envoi : `video:<id>` ou `story:<id>`. Absent des événements de versions statiques.
  kind: 'video' | 'story' | null;
  id: string | null;
  uploadId: string | null;
  assetId: string | null;
}

export class MalformedMuxEventError extends Error {}

// Null : événement sans rapport avec les vidéos (live, pistes…), ignoré.
export function parseMuxEvent(body: unknown): MuxEvent | null {
  const event = record(body);
  const type = text(event?.type);
  if (!event || !type) throw new MalformedMuxEventError('événement Mux sans type');
  if (!type.startsWith('video.asset.') && !type.startsWith('video.upload.')) return null;
  const data = record(event.data);
  const object = record(event.object);
  const objectType = text(object?.type);
  const passthrough = text(data?.passthrough) ?? text(record(data?.new_asset_settings)?.passthrough);
  const match = passthrough?.match(/^(video|story):([0-9a-f-]{36})$/i);
  return {
    type,
    kind: match ? (match[1].toLowerCase() as 'video' | 'story') : null,
    id: match ? match[2].toLowerCase() : null,
    uploadId: (objectType === 'upload' ? text(object?.id) : null) ?? text(data?.upload_id),
    assetId: (objectType === 'asset' ? text(object?.id) : null) ?? text(data?.asset_id),
  };
}

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === 'object' && value !== null && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
}

function text(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}
