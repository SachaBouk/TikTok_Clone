import { describe, expect, it } from 'vitest';
import { createRefresher, REFRESH_REUSE_WINDOW_MS, type RefreshOutcome } from './token-refresh';

const tokens = (n: number) => ({ accessToken: `access-${n}`, accessTokenExpiresIn: 900, refreshToken: `refresh-${n}` });

describe('createRefresher', () => {
  it("n'appelle l'API qu'une fois pour des requêtes simultanées avec le même refresh token", async () => {
    let calls = 0;
    let release!: (outcome: RefreshOutcome) => void;
    const refreshOnce = createRefresher(() => {
      calls++;
      return new Promise((resolve) => (release = resolve));
    });

    const first = refreshOnce('refresh-0');
    const second = refreshOnce('refresh-0');
    release({ kind: 'refreshed', tokens: tokens(1) });

    await expect(first).resolves.toEqual({ kind: 'refreshed', tokens: tokens(1) });
    await expect(second).resolves.toEqual({ kind: 'refreshed', tokens: tokens(1) });
    expect(calls).toBe(1);
  });

  it("resert le même résultat pendant la fenêtre de réemploi, puis l'oublie", async () => {
    let time = 0;
    let calls = 0;
    const refreshOnce = createRefresher(async () => ({ kind: 'refreshed', tokens: tokens(++calls) }), () => time);

    await refreshOnce('refresh-0');
    time += REFRESH_REUSE_WINDOW_MS;
    await expect(refreshOnce('refresh-0')).resolves.toMatchObject({ tokens: tokens(1) });
    time += 1;
    await refreshOnce('autre');
    await expect(refreshOnce('refresh-0')).resolves.toMatchObject({ tokens: tokens(3) });
    expect(calls).toBe(3);
  });

  it('distingue les refresh tokens', async () => {
    let calls = 0;
    const refreshOnce = createRefresher(async () => ({ kind: 'refreshed', tokens: tokens(++calls) }));
    await refreshOnce('a');
    await refreshOnce('b');
    expect(calls).toBe(2);
  });

  it("réessaie après une API injoignable, qui n'a rien consommé", async () => {
    let calls = 0;
    const refreshOnce = createRefresher(async () => {
      if (++calls === 1) throw new Error('ECONNREFUSED');
      return { kind: 'rejected' };
    });
    await expect(refreshOnce('refresh-0')).rejects.toThrow('ECONNREFUSED');
    await expect(refreshOnce('refresh-0')).resolves.toEqual({ kind: 'rejected' });
    expect(calls).toBe(2);
  });
});
