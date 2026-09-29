import { describe, expect, it } from 'vitest';
import { MalformedWebhookError, parseRevenueCatEvent } from './revenuecat-event';

// Exemple de la documentation RevenueCat (webhooks, VIRTUAL_CURRENCY_TRANSACTION), avec deux monnaies.
const body = {
  api_version: '1.0',
  event: {
    type: 'VIRTUAL_CURRENCY_TRANSACTION',
    id: 'UniqueEventID',
    event_timestamp_ms: 1591121855319,
    app_user_id: 'user123',
    original_app_user_id: 'original_user123',
    aliases: ['user123', 'legacy_id'],
    environment: 'PRODUCTION',
    store: 'APP_STORE',
    source: 'in_app_purchase',
    adjustments: [
      { amount: 1000, currency: { code: 'TKN', name: 'Jetons' } },
      { amount: 5, currency: { code: 'GEM', name: 'Gemmes' } },
    ],
    updated_balance: 5000,
    product_id: 'tokens_1000',
    transaction_id: '170000869511114',
  },
};

describe('parseRevenueCatEvent', () => {
  it('lit un mouvement de la monnaie des jetons', () => {
    expect(parseRevenueCatEvent(body, 'TKN')).toEqual({
      eventId: 'UniqueEventID',
      appUserIds: ['user123', 'original_user123', 'legacy_id'],
      amount: 1000,
      source: 'in_app_purchase',
      productId: 'tokens_1000',
      storeTransactionId: '170000869511114',
      store: 'APP_STORE',
      environment: 'PRODUCTION',
      occurredAt: new Date(1591121855319),
    });
  });

  it("compte 0 pour une autre monnaie, et ignore les autres types d'événements", () => {
    expect(parseRevenueCatEvent(body, 'XYZ')).toMatchObject({ amount: 0 });
    expect(parseRevenueCatEvent({ event: { ...body.event, type: 'TEST' } }, 'TKN')).toBeNull();
    expect(parseRevenueCatEvent({ event: { type: 'NON_RENEWING_PURCHASE', id: 'x' } }, 'TKN')).toBeNull();
  });

  it('refuse un corps mal formé', () => {
    expect(() => parseRevenueCatEvent({}, 'TKN')).toThrow(MalformedWebhookError);
    expect(() => parseRevenueCatEvent({ event: { ...body.event, id: undefined } }, 'TKN')).toThrow(MalformedWebhookError);
    expect(() => parseRevenueCatEvent({ event: { ...body.event, adjustments: [{ amount: 1.5 }] } }, 'TKN')).toThrow(MalformedWebhookError);
  });
});
