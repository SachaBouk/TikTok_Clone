import { Logger } from '@nestjs/common';
import type { PushDevice, PushMessage, PushResult } from '../domain/push';
import { PushSender } from '../domain/push-sender';

// Utilisé tant qu'APNs n'est pas configuré (pas de clé .p8, en local) : la notification est journalisée.
export class LoggingPushSender extends PushSender {
  private readonly logger = new Logger('Push');

  async send(device: PushDevice, message: PushMessage): Promise<PushResult> {
    this.logger.log(`(APNs non configuré) ${device.token.slice(0, 8)}… ← ${message.title} : ${message.body}`);
    return 'sent';
  }
}
