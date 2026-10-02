import type { CurrencyEvent } from '../domain/wallet';

// Corps d'un webhook RevenueCat (`{ api_version, event }`), réduit à ce que l'API lit.
// Seuls les événements VIRTUAL_CURRENCY_TRANSACTION changent le solde : RevenueCat les émet pour chaque
// achat, remboursement ou ajustement manuel de la monnaie virtuelle (montant signé par monnaie).
// Les autres types (TEST, NON_RENEWING_PURCHASE…) et les autres monnaies sont ignorés : null.
// Un corps mal formé lève MalformedWebhookError (400 : visible dans le tableau de bord RevenueCat).

export class MalformedWebhookError extends Error {}

export function parseRevenueCatEvent(body: unknown, currencyCode: string): CurrencyEvent | null {
  const event = record(record(body)?.event);
  if (!event) throw new MalformedWebhookError('Champ `event` absent');
  if (event.type !== 'VIRTUAL_CURRENCY_TRANSACTION') return null;

  const eventId = text(event.id);
  const appUserId = text(event.app_user_id);
  const adjustments = Array.isArray(event.adjustments) ? event.adjustments.map(record) : null;
  if (!eventId || !appUserId || !adjustments || adjustments.some((a) => !a || !Number.isInteger(a.amount))) {
    throw new MalformedWebhookError('Événement VIRTUAL_CURRENCY_TRANSACTION incomplet');
  }

  const amount = adjustments.filter((a) => record(a!.currency)?.code === currencyCode).reduce((sum, a) => sum + (a!.amount as number), 0);
  const aliases = Array.isArray(event.aliases) ? event.aliases.map(text).filter((id): id is string => id !== null) : [];
  const timestamp = typeof event.event_timestamp_ms === 'number' ? event.event_timestamp_ms : Date.now();

  return {
    eventId,
    appUserIds: [...new Set([appUserId, text(event.original_app_user_id), ...aliases].filter((id): id is string => id !== null))],
    amount,
    source: text(event.source) ?? 'in_app_purchase',
    productId: text(event.product_id),
    storeTransactionId: text(event.transaction_id),
    store: text(event.store),
    environment: text(event.environment) ?? 'PRODUCTION',
    occurredAt: new Date(timestamp),
  };
}

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === 'object' && value !== null && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
}

function text(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}
