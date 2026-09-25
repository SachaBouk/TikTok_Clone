import { Module } from '@nestjs/common';
import { PushService } from './application/push.service';
import { PushDeviceRepository } from './domain/push-device.repository';
import { PushQueue } from './domain/push-queue';
import { PushSender } from './domain/push-sender';
import { ApnsPushSender } from './infrastructure/apns-push-sender';
import { BullmqPushQueue } from './infrastructure/bullmq-push-queue';
import { LoggingPushSender } from './infrastructure/logging-push-sender';
import { PrismaPushDeviceRepository } from './infrastructure/prisma-push-device.repository';
import { PushController } from './interfaces/push.controller';
import { PushDeliveryConsumer } from './interfaces/push-delivery.consumer';
import { apnsConfigFromEnv } from './push.config';

// Notifications push (APNs), module ajouté à la liste de l'ADR-003. Exporte PushService : videos,
// notifications et messaging lui confient leurs messages. Sans configuration APNs, envoi journalisé.
@Module({
  controllers: [PushController],
  providers: [
    { provide: PushDeviceRepository, useClass: PrismaPushDeviceRepository },
    { provide: PushQueue, useClass: BullmqPushQueue },
    {
      provide: PushSender,
      useFactory: () => {
        const config = apnsConfigFromEnv();
        return config ? new ApnsPushSender(config) : new LoggingPushSender();
      },
    },
    {
      provide: PushService,
      useFactory: (devices: PushDeviceRepository, queue: PushQueue, sender: PushSender) => new PushService(devices, queue, sender),
      inject: [PushDeviceRepository, PushQueue, PushSender],
    },
    PushDeliveryConsumer,
  ],
  exports: [PushService],
})
export class PushModule {}
