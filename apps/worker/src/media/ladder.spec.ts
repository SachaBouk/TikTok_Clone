import { describe, expect, it } from 'vitest';
import { renditionsFor } from './ladder';

const dims = (source: { width: number; height: number }) => renditionsFor(source).map((r) => `${r.name}:${r.width}x${r.height}`);

describe('renditionsFor', () => {
  it('vidéo verticale 1080×1920 : les trois résolutions, en vertical', () => {
    expect(dims({ width: 1080, height: 1920 })).toEqual(['360p:360x640', '720p:720x1280', '1080p:1080x1920']);
  });

  it('vidéo horizontale 1920×1080 : les trois résolutions, en horizontal', () => {
    expect(dims({ width: 1920, height: 1080 })).toEqual(['360p:640x360', '720p:1280x720', '1080p:1920x1080']);
  });

  it('4K verticale : plafonnée à 1080p', () => {
    expect(dims({ width: 2160, height: 3840 })).toEqual(['360p:360x640', '720p:720x1280', '1080p:1080x1920']);
  });

  it("jamais d'agrandissement : une source 720p ne produit pas de 1080p", () => {
    expect(dims({ width: 720, height: 1280 })).toEqual(['360p:360x640', '720p:720x1280']);
  });

  it('source plus petite que 360p : une seule résolution, à sa taille', () => {
    expect(dims({ width: 240, height: 426 })).toEqual(['240p:240x426']);
  });

  it('dimensions toujours paires, même avec un format inhabituel', () => {
    for (const r of renditionsFor({ width: 1179, height: 2556 })) {
      expect(r.width % 2).toBe(0);
      expect(r.height % 2).toBe(0);
    }
    expect(dims({ width: 1179, height: 2556 })).toEqual(['360p:360x780', '720p:720x1560', '1080p:1080x2342']);
  });

  it('débit croissant avec la résolution', () => {
    expect(renditionsFor({ width: 1080, height: 1920 }).map((r) => r.videoKbps)).toEqual([800, 2500, 5000]);
  });
});
