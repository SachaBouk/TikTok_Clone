import { describe, expect, it } from 'vitest';
import { RevenueCatConfig } from './wallet.config';

describe('RevenueCatConfig', () => {
  it('a des valeurs par défaut sans configuration', () => {
    expect(RevenueCatConfig.fromEnv({})).toEqual(new RevenueCatConfig(null, 'TKN', false));
  });

  it('refuse un secret de webhook trop court', () => {
    expect(() => RevenueCatConfig.fromEnv({ REVENUECAT_WEBHOOK_AUTHORIZATION: 'court' })).toThrow();
    expect(RevenueCatConfig.fromEnv({ REVENUECAT_WEBHOOK_AUTHORIZATION: 'Bearer 0123456789abcdef', REVENUECAT_REJECT_SANDBOX: 'true' })).toMatchObject({
      webhookAuthorization: 'Bearer 0123456789abcdef',
      rejectSandbox: true,
    });
  });
});
