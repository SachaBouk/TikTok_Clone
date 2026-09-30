import { describe, expect, it } from 'vitest';
import { RevenueCatConfig } from './wallet.config';

describe('RevenueCatConfig', () => {
  it('a des valeurs par défaut sans configuration : webhook non configuré', () => {
    const config = RevenueCatConfig.fromEnv({});
    expect(config).toEqual(new RevenueCatConfig(null, null, 'TKN', false));
    expect(config.webhookConfigured).toBe(false);
  });

  it('refuse un en-tête ou un secret de signature trop court', () => {
    expect(() => RevenueCatConfig.fromEnv({ REVENUECAT_WEBHOOK_AUTHORIZATION: 'court' })).toThrow();
    expect(() => RevenueCatConfig.fromEnv({ REVENUECAT_WEBHOOK_SIGNING_SECRET: 'court' })).toThrow();
    expect(RevenueCatConfig.fromEnv({ REVENUECAT_WEBHOOK_AUTHORIZATION: 'Bearer 0123456789abcdef', REVENUECAT_REJECT_SANDBOX: 'true' })).toMatchObject({
      webhookAuthorization: 'Bearer 0123456789abcdef',
      webhookSigningSecret: null,
      rejectSandbox: true,
    });
  });

  it('configuré par l’en-tête, par la signature, ou par les deux', () => {
    expect(RevenueCatConfig.fromEnv({ REVENUECAT_WEBHOOK_SIGNING_SECRET: ' secret-de-signature-1234 ' })).toMatchObject({
      webhookAuthorization: null,
      webhookSigningSecret: 'secret-de-signature-1234',
      webhookConfigured: true,
    });
  });
});
