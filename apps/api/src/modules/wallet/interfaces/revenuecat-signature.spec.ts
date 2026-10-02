import { createHmac } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { checkRevenueCatSignature, SIGNATURE_TOLERANCE_SECONDS } from './revenuecat-signature';

const SECRET = 'secret-de-signature-1234';
const NOW = 1_790_000_000;
// Corps tel que reçu (espaces et ordre des clés compris) : la signature porte sur ces octets exacts.
const BODY = Buffer.from('{"api_version":"1.0", "event":{"id":"évt-1","type":"VIRTUAL_CURRENCY_TRANSACTION"}}');

const sign = (t: number, body: Buffer = BODY, secret = SECRET) => createHmac('sha256', secret).update(`${t}.`).update(body).digest('hex');

describe('checkRevenueCatSignature', () => {
  it('accepte une signature calculée sur le corps brut, en-tête avec ou sans espaces', () => {
    expect(checkRevenueCatSignature(`t=${NOW},v1=${sign(NOW)}`, BODY, SECRET, NOW)).toBe('valid');
    expect(checkRevenueCatSignature(`t=${NOW}, v1=${sign(NOW).toUpperCase()}`, BODY, SECRET, NOW + 30)).toBe('valid');
  });

  it('refuse un corps modifié, un autre secret, un horodatage changé', () => {
    const reformatted = Buffer.from(JSON.stringify(JSON.parse(BODY.toString())));
    expect(checkRevenueCatSignature(`t=${NOW},v1=${sign(NOW)}`, reformatted, SECRET, NOW)).toBe('mismatch');
    expect(checkRevenueCatSignature(`t=${NOW},v1=${sign(NOW, BODY, 'autre-secret-5678901')}`, BODY, SECRET, NOW)).toBe('mismatch');
    expect(checkRevenueCatSignature(`t=${NOW + 1},v1=${sign(NOW)}`, BODY, SECRET, NOW)).toBe('mismatch');
  });

  it(`refuse un horodatage à plus de ${SIGNATURE_TOLERANCE_SECONDS} s de l'horloge, dans les deux sens`, () => {
    const old = NOW - SIGNATURE_TOLERANCE_SECONDS;
    expect(checkRevenueCatSignature(`t=${old},v1=${sign(old)}`, BODY, SECRET, NOW)).toBe('valid');
    expect(checkRevenueCatSignature(`t=${old - 1},v1=${sign(old - 1)}`, BODY, SECRET, NOW)).toBe('expired');
    const future = NOW + SIGNATURE_TOLERANCE_SECONDS + 1;
    expect(checkRevenueCatSignature(`t=${future},v1=${sign(future)}`, BODY, SECRET, NOW)).toBe('expired');
  });

  it('accepte si l’une des signatures v1 correspond (rotation du secret)', () => {
    expect(checkRevenueCatSignature(`t=${NOW},v1=${'0'.repeat(64)},v1=${sign(NOW)}`, BODY, SECRET, NOW)).toBe('valid');
  });

  it('en-tête absent ou mal formé, corps absent', () => {
    expect(checkRevenueCatSignature(undefined, BODY, SECRET, NOW)).toBe('missing');
    expect(checkRevenueCatSignature(`t=${NOW},v1=${sign(NOW)}`, undefined, SECRET, NOW)).toBe('missing');
    expect(checkRevenueCatSignature(`v1=${sign(NOW)}`, BODY, SECRET, NOW)).toBe('malformed');
    expect(checkRevenueCatSignature(`t=${NOW}`, BODY, SECRET, NOW)).toBe('malformed');
    expect(checkRevenueCatSignature(`t=abc,v1=${sign(NOW)}`, BODY, SECRET, NOW)).toBe('malformed');
    expect(checkRevenueCatSignature(`t=${NOW},v1=pas-hexa`, BODY, SECRET, NOW)).toBe('mismatch');
    expect(checkRevenueCatSignature(`t=${NOW},v1=${sign(NOW).slice(2)}`, BODY, SECRET, NOW)).toBe('mismatch');
  });
});
