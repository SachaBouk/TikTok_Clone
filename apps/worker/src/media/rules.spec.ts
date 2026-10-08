import { describe, expect, it } from 'vitest';
import { InvalidMediaError } from './ffmpeg';
import { assertPublishable, MAX_STORY_DURATION_SECONDS, MAX_VIDEO_DURATION_SECONDS } from './rules';

describe('assertPublishable', () => {
  it('accepte 3 minutes, à une seconde près (arrondis du conteneur)', () => {
    expect(() => assertPublishable({ durationSeconds: 5 })).not.toThrow();
    expect(() => assertPublishable({ durationSeconds: MAX_VIDEO_DURATION_SECONDS })).not.toThrow();
    expect(() => assertPublishable({ durationSeconds: 180.9 })).not.toThrow();
  });

  it('refuse une vidéo plus longue, comme un fichier invalide (échec définitif, sans relance)', () => {
    expect(() => assertPublishable({ durationSeconds: 181.5 })).toThrow(InvalidMediaError);
    expect(() => assertPublishable({ durationSeconds: 600 })).toThrow('Fichier vidéo invalide : vidéo trop longue (600 s, 180 s au plus)');
  });
});

describe('assertPublishable (story, ADR-051)', () => {
  it('accepte 60 secondes, à une seconde près, et refuse au-delà', () => {
    expect(() => assertPublishable({ durationSeconds: 60.9 }, MAX_STORY_DURATION_SECONDS)).not.toThrow();
    expect(() => assertPublishable({ durationSeconds: 61.5 }, MAX_STORY_DURATION_SECONDS)).toThrow(
      'Fichier vidéo invalide : vidéo trop longue (62 s, 60 s au plus)',
    );
  });
});
