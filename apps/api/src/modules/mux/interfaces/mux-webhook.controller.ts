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
import { checkMuxSignature } from '../../../mux/mux-signature';
import { MuxConfig } from '../../../mux/mux.config';
import { Public } from '../../auth/interfaces/public.decorator';
import { MuxEventsService } from '../application/mux-events.service';
import { MalformedMuxEventError, parseMuxEvent } from '../domain/mux-event';

// Webhook de Mux (ADR-074) : appel de serveur à serveur, hors de la spec OpenAPI. Public pour la garde JWT, authentifié par
// la signature `Mux-Signature` (secret `MUX_WEBHOOK_SECRET` ; sans secret, 503). Mux renvoie l'événement tant qu'il ne
// reçoit pas un 2xx : le traitement (état relu chez Mux) est idempotent et fait avant de répondre.
@ApiExcludeController()
@Public()
@Controller('webhooks')
export class MuxWebhookController {
  private readonly logger = new Logger(MuxWebhookController.name);

  constructor(
    private readonly events: MuxEventsService,
    private readonly config: MuxConfig,
  ) {}

  @Post('mux')
  @HttpCode(200)
  async receiveMuxWebhook(
    @Req() request: RawBodyRequest<Request>,
    @Headers('mux-signature') signature: string | undefined,
    @Body() body: unknown,
  ): Promise<{ status: string }> {
    const secret = this.config.webhookSecret;
    if (!secret) throw new ServiceUnavailableException('Webhook Mux non configuré');
    const check = checkMuxSignature(signature, request.rawBody, secret, Math.floor(Date.now() / 1000));
    if (check !== 'valid') {
      this.logger.warn(`Webhook Mux refusé : signature ${check}`);
      throw new UnauthorizedException();
    }

    let event;
    try {
      event = parseMuxEvent(body);
    } catch (error) {
      if (error instanceof MalformedMuxEventError) throw new BadRequestException(error.message);
      throw error;
    }
    if (!event) return { status: 'ignored' };
    const outcome = await this.events.handle(event);
    this.logger.log(`Événement Mux ${event.type} : ${outcome}`);
    return { status: outcome };
  }
}
