// Dimensions d'une image JPEG ou PNG, lues dans ses premiers octets, sans bibliothèque (ADR-046).
// - PNG : le premier bloc est toujours IHDR (largeur et hauteur aux octets 16 à 23).
// - JPEG : segments parcourus depuis le début jusqu'au premier marqueur SOF (début d'image), qui porte hauteur et
//   largeur. Les segments d'application (EXIF…) le précèdent : il doit se trouver dans les octets lus, sinon l'image
//   est refusée. Les dimensions sont celles stockées, avant toute rotation EXIF (sans effet sur un carré).
// Null si l'en-tête est incomplet ou mal formé.

export interface ImageDimensions {
  width: number;
  height: number;
}

const PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
// « IHDR » en ASCII.
const PNG_IHDR = [0x49, 0x48, 0x44, 0x52];

export function readPngDimensions(bytes: Uint8Array): ImageDimensions | null {
  if (bytes.length < 24) return null;
  if (!PNG_SIGNATURE.every((byte, i) => bytes[i] === byte) || !PNG_IHDR.every((byte, i) => bytes[12 + i] === byte)) return null;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  return positive({ width: view.getUint32(16), height: view.getUint32(20) });
}

export function readJpegDimensions(bytes: Uint8Array): ImageDimensions | null {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return null;
  let offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] !== 0xff) return null;
    const marker = bytes[offset + 1];
    // Octets de remplissage 0xFF entre deux segments.
    if (marker === 0xff) {
      offset += 1;
      continue;
    }
    // Marqueurs sans longueur : TEM, RST0 à RST7.
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
      offset += 2;
      continue;
    }
    // Fin d'image ou début des données compressées avant tout SOF : pas de dimensions.
    if (marker === 0xd9 || marker === 0xda) return null;
    const length = (bytes[offset + 2] << 8) | bytes[offset + 3];
    if (length < 2) return null;
    if (isStartOfFrame(marker)) {
      // Longueur (2), précision (1), hauteur (2), largeur (2).
      if (offset + 9 > bytes.length || length < 7) return null;
      return positive({ height: (bytes[offset + 5] << 8) | bytes[offset + 6], width: (bytes[offset + 7] << 8) | bytes[offset + 8] });
    }
    offset += 2 + length;
  }
  return null;
}

// SOF0 à SOF15, sauf DHT (C4), JPG (C8) et DAC (CC), qui partagent la plage.
function isStartOfFrame(marker: number): boolean {
  return marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc;
}

function positive(dimensions: ImageDimensions): ImageDimensions | null {
  return dimensions.width > 0 && dimensions.height > 0 ? dimensions : null;
}
