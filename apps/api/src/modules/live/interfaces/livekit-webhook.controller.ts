import { Body, Controller, Headers, HttpCode, Logger, Post, UnauthorizedException } from '@nestjs/common';
import { ApiExcludeController } from '@nestjs/swagger';
import { Public } from '../../auth/interfaces/public.decorator';
import { LiveService } from '../application/live.service';
import { LiveMedia } from '../domain/live-media';

// Webhook du serveur LiveKit (ADR-053) : appel de serveur à serveur, hors de la spec OpenAPI. Public pour la garde JWT,
// authentifié par l'en-tête `Authorization` (JWT signé par la clé du serveur, avec l'empreinte du corps). Le corps est
// lu tel quel (`application/webhook+json` en texte, main.ts) : la signature porte sur les octets reçus.
@ApiExcludeController()
@Public()
@Controller('webhooks')
export class LiveKitWebhookController {
  private readonly logger = new Logger('LiveKitWebhook');

  constructor(
    private readonly lives: LiveService,
    private readonly media: LiveMedia,
  ) {}

  @Post('livekit')
  @HttpCode(200)
  async receiveLiveKitWebhook(@Body() body: unknown, @Headers('authorization') authorization: string | undefined): Promise<{ status: string }> {
    const raw = typeof body === 'string' ? body : JSON.stringify(body ?? {});
    let event;
    try {
      event = await this.media.receiveWebhook(raw, authorization);
    } catch (error) {
      this.logger.warn(`Webhook LiveKit refusé : ${(error as Error).message}`);
      throw new UnauthorizedException();
    }
    if (event) await this.lives.handleMediaEvent(event);
    return { status: 'ok' };
  }
}
