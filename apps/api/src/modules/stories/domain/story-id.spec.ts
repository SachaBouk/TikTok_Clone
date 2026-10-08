import { describe, expect, it } from 'vitest';
import { newStoryId } from './story-id';

describe('newStoryId', () => {
  it('produit un UUID v7 dont l’ordre suit le temps', () => {
    const first = newStoryId(1_760_000_000_000);
    const second = newStoryId(1_760_000_000_001);
    expect(first).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
    expect(first < second).toBe(true);
    expect(first.slice(0, 13)).toBe('0199c82c-c000');
  });
});
