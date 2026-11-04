import { Injectable } from '@nestjs/common';
import { PLUS_ENTITLEMENT } from '../domain/plus-subscription';
import { type PlusEntitlement, RevenueCatCustomers } from '../domain/revenuecat-customers';
import { SubscriptionsConfig } from '../subscriptions.config';

// API REST de RevenueCat (v1, `GET /subscribers/{app_user_id}`), avec la clé secrète : jamais dans l'app.
// L'entitlement donne l'échéance (période de grâce comprise) et le produit ; l'abonnement du produit, le store,
// l'environnement et l'annulation du renouvellement.
@Injectable()
export class HttpRevenueCatCustomers extends RevenueCatCustomers {
  constructor(private readonly config: SubscriptionsConfig) {
    super();
  }

  get configured(): boolean {
    return this.config.secretApiKey !== null;
  }

  async fetchPlusEntitlement(appUserId: string): Promise<PlusEntitlement | null> {
    const response = await fetch(`${this.config.apiUrl}/v1/subscribers/${encodeURIComponent(appUserId)}`, {
      headers: { Authorization: `Bearer ${this.config.secretApiKey}`, Accept: 'application/json' },
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) throw new Error(`RevenueCat : HTTP ${response.status} pour le client ${appUserId}`);
    return parsePlusEntitlement(await response.json());
  }
}

// Exporté pour les tests (forme de la réponse de RevenueCat).
export function parsePlusEntitlement(body: unknown): PlusEntitlement | null {
  const subscriber = record(record(body)?.subscriber);
  const entitlement = record(record(subscriber?.entitlements)?.[PLUS_ENTITLEMENT]);
  const productId = text(entitlement?.product_identifier);
  const expiresAt = latest(date(entitlement?.expires_date), date(entitlement?.grace_period_expires_date));
  if (!entitlement || !productId || !expiresAt) return null;
  const subscription = record(record(subscriber?.subscriptions)?.[productId]);
  const store = text(subscription?.store);
  return {
    productId,
    expiresAt,
    willRenew: subscription ? subscription.unsubscribe_detected_at == null : true,
    store,
    sandbox: subscription?.is_sandbox === true || store === 'test_store',
  };
}

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === 'object' && value !== null && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
}

function text(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function date(value: unknown): Date | null {
  const parsed = typeof value === 'string' ? new Date(value) : null;
  return parsed && !Number.isNaN(parsed.getTime()) ? parsed : null;
}

function latest(a: Date | null, b: Date | null): Date | null {
  if (!a) return b;
  if (!b) return a;
  return a > b ? a : b;
}
