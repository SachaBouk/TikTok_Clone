import { describe, expect, it } from 'vitest';
import { withQuery } from './format';

describe('withQuery', () => {
  it('ne garde que les paramètres renseignés', () => {
    expect(withQuery('/videos', { status: 'failed', userId: null, cursor: '' })).toBe('/videos?status=failed');
    expect(withQuery('/videos', {})).toBe('/videos');
    expect(withQuery('/users', { q: '@léa b' })).toBe('/users?q=%40l%C3%A9a+b');
  });
});
