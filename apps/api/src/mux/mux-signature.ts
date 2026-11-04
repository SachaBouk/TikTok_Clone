import { createHmac, timingSafeEqual } from 'node:crypto';

// Signature des webhooks de Mux (ADR-074) : en-tête `Mux-Signature: t=<unix>,v1=<hex>`, HMAC-SHA256 de `<t>.<corps brut>`
// avec le secret du webhook. Même principe que RevenueCat (ADR-031) : le corps doit être celui reçu, octet pour octet.

// Écart admis entre `t` et l'horloge de l'API (valeur des SDK de Mux).
export const MUX_SIGNATURE_TOLERANCE_SECONDS = 5 * 60;

export type MuxSignatureCheck = 'valid' | 'missing' | 'malformed' | 'expired' | 'mismatch';

export function checkMuxSignature(header: string | undefined, rawBody: Buffer | undefined, secret: string, nowSeconds: number): MuxSignatureCheck {
  if (!header || !rawBody) return 'missing';
  const parts = header.split(',').map((part) => part.trim().split('='));
  const timestamp = parts.find(([name]) => name === 't')?.[1];
  const signatures = parts.filter(([name, value]) => name === 'v1' && value).map(([, value]) => value);
  if (!timestamp || !/^\d+$/.test(timestamp) || signatures.length === 0) return 'malformed';
  if (Math.abs(nowSeconds - Number(timestamp)) > MUX_SIGNATURE_TOLERANCE_SECONDS) return 'expired';

  const expected = createHmac('sha256', secret).update(`${timestamp}.`).update(rawBody).digest();
  const matches = signatures.some((signature) => /^[0-9a-f]{64}$/i.test(signature) && timingSafeEqual(Buffer.from(signature, 'hex'), expected));
  return matches ? 'valid' : 'mismatch';
}
