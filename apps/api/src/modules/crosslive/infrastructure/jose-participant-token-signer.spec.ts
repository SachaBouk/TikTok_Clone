import { jwtVerify } from 'jose';
import { describe, expect, it } from 'vitest';
import { CrossLiveUnavailableError } from '../domain/participant-token';
import { crossLiveConfigFromEnv } from './crosslive.config';
import { JoseParticipantTokenSigner } from './jose-participant-token-signer';

describe('JoseParticipantTokenSigner', () => {
  it('signe un JWT HS256 de 5 min avec l’App membre pour émetteur', async () => {
    const signer = new JoseParticipantTokenSigner({ appId: 'tiktok', secret: 'secret-de-test' });
    const token = await signer.sign({ sub: 'u-1', name: 'lea', picture: 'https://cdn.example.com/a.jpg' });

    const { payload, protectedHeader } = await jwtVerify(token, new TextEncoder().encode('secret-de-test'), { issuer: 'tiktok' });
    expect(protectedHeader.alg).toBe('HS256');
    expect(payload).toMatchObject({ sub: 'u-1', name: 'lea', picture: 'https://cdn.example.com/a.jpg' });
    expect(payload.exp! - payload.iat!).toBe(300);
  });

  it('n’est pas disponible sans secret', async () => {
    const signer = new JoseParticipantTokenSigner(crossLiveConfigFromEnv({}));

    expect(signer.available).toBe(false);
    await expect(signer.sign({ sub: 'u-1', name: 'lea' })).rejects.toBeInstanceOf(CrossLiveUnavailableError);
  });

  it('prend `tiktok` pour App membre par défaut', () => {
    expect(crossLiveConfigFromEnv({ LIVE_SDK_TOKEN_SECRET: ' s ' })).toEqual({ appId: 'tiktok', secret: 's' });
  });
});
