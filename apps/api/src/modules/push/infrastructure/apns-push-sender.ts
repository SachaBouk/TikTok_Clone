import { connect, constants, type ClientHttp2Session } from 'node:http2';
import { Logger, OnModuleDestroy } from '@nestjs/common';
import { importPKCS8, SignJWT } from 'jose';
import type { PushDevice, PushMessage, PushResult } from '../domain/push';
import { PushSender } from '../domain/push-sender';
import type { ApnsConfig } from '../push.config';

const HOSTS = { production: 'https://api.push.apple.com', sandbox: 'https://api.sandbox.push.apple.com' } as const;
// Apple refuse un jeton de plus d'une heure, et un renouvellement plus d'une fois toutes les 20 minutes.
const TOKEN_TTL_MS = 50 * 60_000;
const REQUEST_TIMEOUT_MS = 10_000;
// Raisons APNs pour lesquelles le token est définitivement inutilisable.
const INVALID_TOKEN_REASONS = new Set(['BadDeviceToken', 'DeviceTokenNotForTopic', 'Unregistered']);

// Envoi direct à APNs : HTTP/2, authentification par jeton JWT ES256 signé avec la clé .p8.
// Une connexion HTTP/2 par serveur (production, sandbox), ouverte au premier envoi et réutilisée.
export class ApnsPushSender extends PushSender implements OnModuleDestroy {
  private readonly logger = new Logger('Apns');
  private readonly sessions = new Map<string, ClientHttp2Session>();
  private token: { value: string; issuedAt: number } | null = null;

  constructor(private readonly config: ApnsConfig) {
    super();
  }

  async send(device: PushDevice, message: PushMessage): Promise<PushResult> {
    const payload = JSON.stringify({
      aps: { alert: { title: message.title, body: message.body }, sound: 'default', 'thread-id': message.threadId },
      ...message.data,
    });
    const { status, reason } = await this.post(this.config.hostOverride ?? HOSTS[device.environment], device.token, payload);
    if (status === 200) return 'sent';
    if (status === 410 || (status === 400 && INVALID_TOKEN_REASONS.has(reason))) return 'invalidToken';
    // Jeton d'authentification refusé (expiré, horloge décalée) : régénéré à la prochaine tentative.
    if (status === 403) this.token = null;
    throw new Error(`APNs ${status} ${reason}`);
  }

  async onModuleDestroy() {
    for (const session of this.sessions.values()) session.close();
    this.sessions.clear();
  }

  private async post(host: string, token: string, payload: string): Promise<{ status: number; reason: string }> {
    const authorization = `bearer ${await this.authToken()}`;
    return new Promise((resolve, reject) => {
      const request = this.session(host).request({
        ':method': 'POST',
        ':path': `/3/device/${token}`,
        authorization,
        'apns-topic': this.config.topic,
        'apns-push-type': 'alert',
        'apns-priority': '10',
        // Conservée 24 h par APNs si l'appareil est hors ligne.
        'apns-expiration': String(Math.floor(Date.now() / 1000) + 24 * 3600),
        'content-type': 'application/json',
      });
      let status = 0;
      let body = '';
      request.setTimeout(REQUEST_TIMEOUT_MS, () => request.close(constants.NGHTTP2_CANCEL));
      request.on('response', (headers) => (status = Number(headers[':status'])));
      request.setEncoding('utf8');
      request.on('data', (chunk: string) => (body += chunk));
      request.on('end', () => {
        let reason = '';
        try {
          reason = body ? ((JSON.parse(body) as { reason?: string }).reason ?? '') : '';
        } catch {
          reason = body;
        }
        if (status === 0) reject(new Error('APNs : pas de réponse'));
        else resolve({ status, reason });
      });
      request.on('error', reject);
      request.end(payload);
    });
  }

  private session(host: string): ClientHttp2Session {
    const existing = this.sessions.get(host);
    if (existing && !existing.closed && !existing.destroyed) return existing;
    const session = connect(host);
    const forget = () => {
      if (this.sessions.get(host) === session) this.sessions.delete(host);
    };
    session.on('error', (error) => {
      this.logger.warn(`Connexion APNs ${host} : ${error.message}`);
      forget();
    });
    session.on('close', forget);
    session.on('goaway', forget);
    // Ne retient pas le processus à l'arrêt.
    session.unref();
    this.sessions.set(host, session);
    return session;
  }

  private async authToken(): Promise<string> {
    if (this.token && Date.now() - this.token.issuedAt < TOKEN_TTL_MS) return this.token.value;
    const key = await importPKCS8(this.config.privateKey, 'ES256');
    const value = await new SignJWT({})
      .setProtectedHeader({ alg: 'ES256', kid: this.config.keyId })
      .setIssuer(this.config.teamId)
      .setIssuedAt()
      .sign(key);
    this.token = { value, issuedAt: Date.now() };
    return value;
  }
}
