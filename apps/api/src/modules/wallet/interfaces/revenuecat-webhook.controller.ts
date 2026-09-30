import {
  BadRequestException,
  Body,
  Controller,
  Headers,
  HttpCode,
  Logger,
  Post,
  type RawBodyRequest,
  Req,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { ApiExcludeController } from '@nestjs/swagger';
import type { Request } from 'express';
import { createHash, timingSafeEqual } from 'node:crypto';
import { Public } from '../../auth/interfaces/public.decorator';
import { WalletService } from '../application/wallet.service';
import { RevenueCatConfig } from '../wallet.config';
import { MalformedWebhookError, parseRevenueCatEvent } from './revenuecat-event';
import { checkRevenueCatSignature } from './revenuecat-signature';

// Webhook RevenueCat (ADR-009) : appel de serveur à serveur, hors de la spec OpenAPI (aucun client à générer).
// Public pour la garde JWT : authentifié par l'en-tête `Authorization` configuré dans RevenueCat, et par la
// signature HMAC `X-RevenueCat-Webhook-Signature` si son secret est configuré (ADR-031). Chaque protection
// configurée est exigée (401 sinon) ; sans aucune, 503.
// RevenueCat renvoie l'événement (même `id`) tant qu'il ne reçoit pas un 200 : 5 essais sur environ 2 h 30.
// Le traitement est idempotent et rapide (une transaction), donc fait avant de répondre.
@ApiExcludeController()
@Public()
@Controller('webhooks')
export class RevenueCatWebhookController {
  private readonly logger = new Logger(RevenueCatWebhookController.name);

  constructor(
    private readonly walletService: WalletService,
    private readonly config: RevenueCatConfig,
  ) {}

  @Post('revenuecat')
  @HttpCode(200)
  async receiveRevenueCatWebhook(
    @Req() request: RawBodyRequest<Request>,
    @Headers('authorization') authorization: string | undefined,
    @Headers('x-revenuecat-webhook-signature') signature: string | undefined,
    @Body() body: unknown,
  ): Promise<{ status: string }> {
    const { webhookAuthorization, webhookSigningSecret } = this.config;
    if (!this.config.webhookConfigured) throw new ServiceUnavailableException('Webhook RevenueCat non configuré');
    if (webhookAuthorization && !sameSecret(authorization ?? '', webhookAuthorization)) throw new UnauthorizedException();
    if (webhookSigningSecret) {
      const check = checkRevenueCatSignature(signature, request.rawBody, webhookSigningSecret, Math.floor(Date.now() / 1000));
      if (check !== 'valid') {
        this.logger.warn(`Webhook RevenueCat refusé : signature ${check}`);
        throw new UnauthorizedException();
      }
    }

    let event;
    try {
      event = parseRevenueCatEvent(body, this.config.currencyCode);
    } catch (error) {
      if (error instanceof MalformedWebhookError) throw new BadRequestException(error.message);
      throw error;
    }
    if (!event) return { status: 'ignored' };

    const outcome = await this.walletService.recordCurrencyEvent(event);
    const log = `Événement RevenueCat ${event.eventId} (${event.amount} jetons, ${event.environment}) : ${outcome}`;
    if (outcome === 'unknownCustomer') this.logger.warn(`${log}, client ${event.appUserIds.join(', ')} à rapprocher`);
    else this.logger.log(log);
    return { status: outcome };
  }
}

// Comparaison en temps constant (hachés pour avoir la même longueur).
function sameSecret(received: string, expected: string): boolean {
  const digest = (value: string) => createHash('sha256').update(value).digest();
  return timingSafeEqual(digest(received), digest(expected));
}
