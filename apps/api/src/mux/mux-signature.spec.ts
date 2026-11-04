import { createHmac } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { checkMuxSignature, MUX_SIGNATURE_TOLERANCE_SECONDS } from './mux-signature';

const SECRET = 'secret-du-webhook-mux';
const NOW = 1_790_000_000;
// Corps tel que reçu : la signature porte sur ces octets exacts.
const BODY = Buffer.from('{"type":"video.asset.ready", "data":{"id":"asset-1","passthrough":"video:x"}}');

const sign = (t: number, body: Buffer = BODY, secret = SECRET) => createHmac('sha256', secret).update(`${t}.`).update(body).digest('hex');

describe('checkMuxSignature', () => {
  it('accepte une signature calculée sur le corps brut', () => {
    expect(checkMuxSignature(`t=${NOW},v1=${sign(NOW)}`, BODY, SECRET, NOW)).toBe('valid');
    expect(checkMuxSignature(`t=${NOW}, v1=${sign(NOW)}`, BODY, SECRET, NOW + 60)).toBe('valid');
  });

  it('refuse un corps réécrit, un autre secret', () => {
    const reformatted = Buffer.from(JSON.stringify(JSON.parse(BODY.toString())));
    expect(checkMuxSignature(`t=${NOW},v1=${sign(NOW)}`, reformatted, SECRET, NOW)).toBe('mismatch');
    expect(checkMuxSignature(`t=${NOW},v1=${sign(NOW, BODY, 'autre')}`, BODY, SECRET, NOW)).toBe('mismatch');
  });

  it('refuse un horodatage trop ancien ou trop lointain', () => {
    const old = NOW - MUX_SIGNATURE_TOLERANCE_SECONDS - 1;
    expect(checkMuxSignature(`t=${old},v1=${sign(old)}`, BODY, SECRET, NOW)).toBe('expired');
  });

  it('refuse un en-tête absent ou mal formé', () => {
    expect(checkMuxSignature(undefined, BODY, SECRET, NOW)).toBe('missing');
    expect(checkMuxSignature(`t=${NOW}`, BODY, SECRET, NOW)).toBe('malformed');
    expect(checkMuxSignature(`v1=${sign(NOW)}`, BODY, SECRET, NOW)).toBe('malformed');
    expect(checkMuxSignature(`t=${NOW},v1=zz`, BODY, SECRET, NOW)).toBe('mismatch');
  });
});
