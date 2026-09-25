// Échelle de résolutions HLS (ADR-008 : 360p, 720p, 1080p).
// Le « p » désigne le petit côté de l'image, pour traiter pareil le vertical (format TikTok) et l'horizontal :
// une vidéo verticale 1080×1920 donne 360×640, 720×1280 et 1080×1920.

export interface Rendition {
  name: string;
  width: number;
  height: number;
  // Débit vidéo cible, en kbit/s (H.264).
  videoKbps: number;
}

const LADDER = [
  { name: '360p', shortSide: 360, videoKbps: 800 },
  { name: '720p', shortSide: 720, videoKbps: 2500 },
  { name: '1080p', shortSide: 1080, videoKbps: 5000 },
] as const;

// Dimensions affichées de la source (rotation déjà appliquée).
export function renditionsFor(source: { width: number; height: number }): Rendition[] {
  const shortSide = Math.min(source.width, source.height);
  // Jamais d'agrandissement : seules les résolutions inférieures ou égales à la source sont produites.
  const steps = LADDER.filter((step) => step.shortSide <= shortSide);
  // Source plus petite que 360p : une seule résolution, à la taille de la source.
  if (steps.length === 0) {
    return [{ name: `${even(shortSide)}p`, ...scaled(source, shortSide), videoKbps: LADDER[0].videoKbps }];
  }
  return steps.map((step) => ({ name: step.name, ...scaled(source, step.shortSide), videoKbps: step.videoKbps }));
}

function scaled(source: { width: number; height: number }, targetShortSide: number) {
  const portrait = source.height >= source.width;
  const factor = targetShortSide / Math.min(source.width, source.height);
  const short = even(targetShortSide);
  const long = even(Math.max(source.width, source.height) * factor);
  return portrait ? { width: short, height: long } : { width: long, height: short };
}

// H.264 en 4:2:0 exige des dimensions paires.
function even(value: number): number {
  return Math.max(2, Math.round(value / 2) * 2);
}
