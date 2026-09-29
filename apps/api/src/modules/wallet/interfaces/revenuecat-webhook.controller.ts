import { BadRequestException, Body, Controller, Headers, HttpCode, Logger, Post, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { ApiExcludeController } from '@nestjs/swagger';
import { createHash, timingSafeEqual } from 'node:crypto';
import { Public } from '../../auth/interfaces/public.decorator';
import { WalletService } from '../application/wallet.service';
import { RevenueCatConfig } from '../wallet.config';
import { MalformedWebhookError, parseRevenueCatEvent } from './revenuecat-event';

// Webhook RevenueCat (ADR-009) : appel de serveur à serveur, hors de la spec OpenAPI (aucun client à générer).
// Public pour la garde JWT : authentifié par l'en-tête `Authorization` configuré dans RevenueCat.
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
  async receiveRevenueCatWebhook(@Headers('authorization') authorization: string | undefined, @Body() body: unknown): Promise<{ status: string }> {
    if (!this.config.webhookAuthorization) throw new ServiceUnavailableException('Webhook RevenueCat non configuré');
    if (!sameSecret(authorization ?? '', this.config.webhookAuthorization)) throw new UnauthorizedException();

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
