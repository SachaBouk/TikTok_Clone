import { generateKeyPairSync } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { MuxConfig } from './mux.config';

const pem = generateKeyPairSync('rsa', { modulusLength: 2048 }).privateKey.export({ type: 'pkcs1', format: 'pem' }).toString();
const complete = {
  VIDEO_PROVIDER: 'mux',
  MUX_TOKEN_ID: 'id',
  MUX_TOKEN_SECRET: 'secret',
  MUX_WEBHOOK_SECRET: 'webhook',
  MUX_SIGNING_KEY_ID: 'key',
  MUX_SIGNING_KEY: Buffer.from(pem).toString('base64'),
};

describe('MuxConfig', () => {
  it('pipeline maison par défaut, sans clé', () => {
    const config = MuxConfig.fromEnv({});
    expect(config.provider).toBe('local');
    expect(config.apiConfigured).toBe(false);
    expect(config.apiUrl).toBe('https://api.mux.com');
  });

  it('lit toutes les clés en mode mux, clé de signature encodée en base64', () => {
    const config = MuxConfig.fromEnv(complete);
    expect(config.provider).toBe('mux');
    expect(config.apiConfigured).toBe(true);
    expect(config.signingKey?.asymmetricKeyType).toBe('rsa');
  });

  it('refuse le mode mux avec une clé manquante, une valeur inconnue, une clé illisible', () => {
    expect(() => MuxConfig.fromEnv({ ...complete, MUX_WEBHOOK_SECRET: '' })).toThrow(/MUX_WEBHOOK_SECRET/);
    expect(() => MuxConfig.fromEnv({ VIDEO_PROVIDER: 'cloudflare' })).toThrow(/VIDEO_PROVIDER/);
    expect(() => MuxConfig.fromEnv({ ...complete, MUX_SIGNING_KEY: 'pas-une-cle' })).toThrow(/MUX_SIGNING_KEY/);
  });
});
