import { createHmac, timingSafeEqual } from 'node:crypto';

// Signature HMAC des webhooks RevenueCat (ADR-031). En-tête `X-RevenueCat-Webhook-Signature: t=<unix>,v1=<hex>` :
// HMAC-SHA256, avec le secret de signature (tel quel) pour clé, de `<t>.<corps brut>`. Le corps doit être celui
// reçu, octet pour octet : un JSON relu puis réécrit ne donnerait pas la même signature. RevenueCat recalcule
// `t` et `v1` à chaque envoi, relances comprises.

// Écart admis entre `t` et l'horloge de l'API : décalage d'horloge et durée de l'envoi (recommandation de
// RevenueCat). Un rejeu dans ce délai est sans effet : l'événement est idempotent (identifiant RevenueCat).
export const SIGNATURE_TOLERANCE_SECONDS = 5 * 60;

export type SignatureCheck = 'valid' | 'missing' | 'malformed' | 'expired' | 'mismatch';

export function checkRevenueCatSignature(
  header: string | undefined,
  rawBody: Buffer | undefined,
  secret: string,
  nowSeconds: number,
): SignatureCheck {
  if (!header || !rawBody) return 'missing';
  const parts = header.split(',').map((part) => part.trim().split('='));
  const timestamp = parts.find(([name]) => name === 't')?.[1];
  // Plusieurs `v1` possibles (rotation du secret) : une seule doit correspondre.
  const signatures = parts.filter(([name, value]) => name === 'v1' && value).map(([, value]) => value);
  if (!timestamp || !/^\d+$/.test(timestamp) || signatures.length === 0) return 'malformed';
  if (Math.abs(nowSeconds - Number(timestamp)) > SIGNATURE_TOLERANCE_SECONDS) return 'expired';

  const expected = createHmac('sha256', secret).update(`${timestamp}.`).update(rawBody).digest();
  const matches = signatures.some((signature) => {
    if (!/^[0-9a-f]{64}$/i.test(signature)) return false;
    return timingSafeEqual(Buffer.from(signature, 'hex'), expected);
  });
  return matches ? 'valid' : 'mismatch';
}
