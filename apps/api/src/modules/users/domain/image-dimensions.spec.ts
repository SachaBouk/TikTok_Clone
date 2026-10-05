import { describe, expect, it } from 'vitest';
import { readJpegDimensions, readPngDimensions } from './image-dimensions';
import { AVATAR_HEADER_LENGTH, avatarDimensions, isValidAvatarContent, isValidAvatarDimensions } from './profile-rules';

// Vraies images, générées avec FFmpeg (JPEG 64 × 64, PNG 64 × 48) et `sips` de macOS (JPEG 64 × 48 avec segments JFIF,
// EXIF et Photoshop avant le marqueur SOF, comme ceux d'un iPhone).
const FFMPEG_JPEG_64 = fromBase64(
  '/9j/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjExLjEwMAD/2wBDAAgUFBcUFxsbGxsbGyAeICEhISAgICAhISEkJCQqKiokJCQhISQkKCgqKi4vLisrKisvLzIyMjw8OTlGRkhWVmf/xABNAAEBAAAAAAAAAAAAAAAAAAAABgEBAQEAAAAAAAAAAAAAAAAAAAYHEAEAAAAAAAAAAAAAAAAAAAAAEQEAAAAAAAAAAAAAAAAAAAAA/8AAEQgAQABAAwEiAAIRAAMRAP/aAAwDAQACEQMRAD8AiwEm38AAAAAAAAAAAAAAAAAAAAAAAAAAAAAB/9k=',
);
const SIPS_JPEG_64X48 = fromBase64(
  '/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAQKADAAQAAAABAAAAMAAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgAMABAAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMACQkJCQkJEAkJEBYQEBAWHhYWFhYeJh4eHh4eJi4mJiYmJiYuLi4uLi4uLjc3Nzc3N0BAQEBASEhISEhISEhISP/bAEMBCwwMEhESHxERH0szKjNLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS//dAAQABP/aAAwDAQACEQMRAD8A8nooor9cOAKKKKACiiigAooooA//0PJ6KKK/XDgCiiigAooooAKKKKAP/9Hyeiiiv1w4AooooAKKKKACiiigD//Z',
);
const FFMPEG_PNG_64X48 = fromBase64(
  'iVBORw0KGgoAAAANSUhEUgAAAEAAAAAwCAIAAAAuKetIAAAACXBIWXMAAAABAAAAAQBPJcTWAAAAUUlEQVR4nO3PwQkAIBDAsBPcf2PBIXwEoZmgXTNnfrZ1wKsGtAa0BrQGtAa0BrQGtAa0BrQGtAa0BrQGtAa0BrQGtAa0BrQGtAa0BrQGtAa0C1VYAbuE4JSQAAAAAElFTkSuQmCC',
);

function fromBase64(text: string): Uint8Array {
  return Uint8Array.from(Buffer.from(text, 'base64'));
}

// En-tête JPEG minimal : SOI, un segment APP1 de `app1Length` octets, puis le marqueur `sof` (SOF0 par défaut).
function jpegHeader(width: number, height: number, { sof = 0xc0, app1Length = 16 } = {}): Uint8Array {
  const app1 = [0xff, 0xe1, (app1Length + 2) >> 8, (app1Length + 2) & 0xff, ...new Array<number>(app1Length).fill(0)];
  const frame = [0xff, sof, 0x00, 0x11, 0x08, height >> 8, height & 0xff, width >> 8, width & 0xff, 0x03, ...new Array<number>(9).fill(0)];
  return Uint8Array.from([0xff, 0xd8, ...app1, ...frame]);
}

describe('dimensions d’une image (ADR-046)', () => {
  it('lit les vraies images JPEG et PNG', () => {
    expect(readJpegDimensions(FFMPEG_JPEG_64)).toEqual({ width: 64, height: 64 });
    expect(readJpegDimensions(SIPS_JPEG_64X48)).toEqual({ width: 64, height: 48 });
    expect(readPngDimensions(FFMPEG_PNG_64X48)).toEqual({ width: 64, height: 48 });
  });

  it('JPEG : SOF progressif, segments longs avant le SOF, octets de remplissage', () => {
    expect(readJpegDimensions(jpegHeader(512, 512, { sof: 0xc2 }))).toEqual({ width: 512, height: 512 });
    expect(readJpegDimensions(jpegHeader(300, 200, { app1Length: 40_000 }))).toEqual({ width: 300, height: 200 });
    const padded = jpegHeader(128, 128);
    expect(readJpegDimensions(Uint8Array.from([...padded.subarray(0, 2), 0xff, 0xff, ...padded.subarray(2)]))).toEqual({ width: 128, height: 128 });
    // DHT (C4) n'est pas un SOF : il est sauté.
    const dht = [0xff, 0xc4, 0x00, 0x04, 0x00, 0x00];
    expect(readJpegDimensions(Uint8Array.from([0xff, 0xd8, ...dht, ...jpegHeader(96, 96).subarray(2)]))).toEqual({ width: 96, height: 96 });
  });

  it('refuse un en-tête incomplet, sans SOF, mal formé ou de dimensions nulles', () => {
    expect(readJpegDimensions(jpegHeader(512, 512).subarray(0, 30))).toBeNull();
    // SOF au-delà des octets lus.
    expect(readJpegDimensions(jpegHeader(512, 512, { app1Length: 70_000 }).subarray(0, AVATAR_HEADER_LENGTH))).toBeNull();
    // Début des données compressées (SOS) avant tout SOF.
    expect(readJpegDimensions(Uint8Array.from([0xff, 0xd8, 0xff, 0xda, 0x00, 0x08, 0, 0, 0, 0, 0, 0]))).toBeNull();
    expect(readJpegDimensions(Uint8Array.from([0xff, 0xd8, 0xff, 0xe1, 0x00, 0x01, 0, 0]))).toBeNull();
    expect(readJpegDimensions(Uint8Array.from([0xff, 0xd8, 0x00, 0x00, 0, 0]))).toBeNull();
    expect(readJpegDimensions(jpegHeader(0, 512))).toBeNull();
    expect(readJpegDimensions(FFMPEG_PNG_64X48)).toBeNull();
    expect(readPngDimensions(FFMPEG_PNG_64X48.subarray(0, 20))).toBeNull();
    expect(readPngDimensions(FFMPEG_JPEG_64)).toBeNull();
  });

  it('photo de profil : carré de 64 à 2048 px, du type déclaré', () => {
    expect(isValidAvatarDimensions({ width: 512, height: 512 })).toBe(true);
    expect(isValidAvatarDimensions({ width: 64, height: 64 })).toBe(true);
    expect(isValidAvatarDimensions({ width: 2048, height: 2048 })).toBe(true);
    expect(isValidAvatarDimensions({ width: 63, height: 63 })).toBe(false);
    expect(isValidAvatarDimensions({ width: 2049, height: 2049 })).toBe(false);
    expect(isValidAvatarDimensions({ width: 512, height: 511 })).toBe(false);

    expect(isValidAvatarContent('image/jpeg', FFMPEG_JPEG_64)).toBe(true);
    expect(isValidAvatarContent('image/jpeg', SIPS_JPEG_64X48)).toBe(false);
    expect(isValidAvatarContent('image/png', FFMPEG_PNG_64X48)).toBe(false);
    expect(isValidAvatarContent('image/png', FFMPEG_JPEG_64)).toBe(false);
    expect(avatarDimensions('image/png', FFMPEG_PNG_64X48)).toEqual({ width: 64, height: 48 });
  });
});
