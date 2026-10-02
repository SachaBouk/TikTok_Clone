import { generateKeyPairSync } from 'node:crypto';
import { createServer, type Http2Server, type IncomingHttpHeaders } from 'node:http2';
import type { AddressInfo } from 'node:net';
import { jwtVerify } from 'jose';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { apnsConfigFromEnv } from '../push.config';
import { ApnsPushSender } from './apns-push-sender';

// Faux serveur APNs local (HTTP/2 en clair, h2c) : vérifie la requête réelle de l'adaptateur.
const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
const TOKEN = 'ab'.repeat(32);
const message = { title: 'Léa Martin', body: 'Salut !', threadId: 'conversation:c1', data: { type: 'message', conversationId: 'c1' } };

describe('ApnsPushSender', () => {
  let server: Http2Server;
  let sender: ApnsPushSender;
  let requests: { headers: IncomingHttpHeaders; body: string }[];
  let reply: { status: number; reason?: string };

  beforeAll(async () => {
    server = createServer((request, response) => {
      let body = '';
      request.on('data', (chunk: Buffer) => (body += chunk.toString()));
      request.on('end', () => {
        requests.push({ headers: request.headers, body });
        response.writeHead(reply.status, { 'content-type': 'application/json' });
        response.end(reply.reason ? JSON.stringify({ reason: reply.reason }) : '');
      });
    });
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
    const { port } = server.address() as AddressInfo;
    const config = apnsConfigFromEnv({
      APNS_KEY: privateKey.export({ format: 'pem', type: 'pkcs8' }).toString().replace(/\n/g, '\\n'),
      APNS_KEY_ID: 'KEY123',
      APNS_TEAM_ID: 'TEAM456',
      APPLE_BUNDLE_ID: 'com.example.app',
      APNS_HOST: `http://127.0.0.1:${port}`,
    });
    sender = new ApnsPushSender(config!);
  });

  afterAll(async () => {
    await sender.onModuleDestroy();
    await new Promise((resolve) => server.close(resolve));
  });

  beforeEach(() => {
    requests = [];
    reply = { status: 200 };
  });

  it('envoie une alerte authentifiée par un JWT ES256, avec le payload attendu', async () => {
    await expect(sender.send({ token: TOKEN, userId: 'u', environment: 'production' }, message)).resolves.toBe('sent');

    const [{ headers, body }] = requests as [{ headers: IncomingHttpHeaders; body: string }];
    expect(headers).toMatchObject({
      ':method': 'POST',
      ':path': `/3/device/${TOKEN}`,
      'apns-topic': 'com.example.app',
      'apns-push-type': 'alert',
      'apns-priority': '10',
    });
    const jwt = String(headers.authorization).replace(/^bearer /, '');
    const { payload, protectedHeader } = await jwtVerify(jwt, publicKey, { issuer: 'TEAM456' });
    expect(protectedHeader).toMatchObject({ alg: 'ES256', kid: 'KEY123' });
    expect(typeof payload.iat).toBe('number');
    expect(JSON.parse(body)).toEqual({
      aps: { alert: { title: 'Léa Martin', body: 'Salut !' }, sound: 'default', 'thread-id': 'conversation:c1' },
      type: 'message',
      conversationId: 'c1',
    });
  });

  it('réutilise le jeton et la connexion d’un envoi à l’autre', async () => {
    await sender.send({ token: TOKEN, userId: 'u', environment: 'sandbox' }, message);
    await sender.send({ token: TOKEN, userId: 'u', environment: 'sandbox' }, message);
    expect(requests[0].headers.authorization).toBe(requests[1].headers.authorization);
  });

  it('token invalide (410, BadDeviceToken) → invalidToken ; autre échec → erreur (relance)', async () => {
    const device = { token: TOKEN, userId: 'u', environment: 'production' as const };
    reply = { status: 410, reason: 'Unregistered' };
    await expect(sender.send(device, message)).resolves.toBe('invalidToken');
    reply = { status: 400, reason: 'BadDeviceToken' };
    await expect(sender.send(device, message)).resolves.toBe('invalidToken');
    reply = { status: 400, reason: 'PayloadTooLarge' };
    await expect(sender.send(device, message)).rejects.toThrow('APNs 400 PayloadTooLarge');
    reply = { status: 503, reason: 'ServiceUnavailable' };
    await expect(sender.send(device, message)).rejects.toThrow('APNs 503');
  });
});

describe('apnsConfigFromEnv', () => {
  it('désactivé sans configuration, erreur si incomplète', () => {
    expect(apnsConfigFromEnv({})).toBeNull();
    expect(() => apnsConfigFromEnv({ APNS_KEY_ID: 'K' })).toThrow('Configuration APNs incomplète');
  });
});
