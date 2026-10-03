import { Injectable } from '@nestjs/common';
import { RealtimeService } from '../../realtime/application/realtime.service';
import { type ProfileCounters, ProfileCountersPublisher } from '../domain/profile-counters-publisher';

// Pousse les compteurs du profil au compte concerné, sur tous ses appareils connectés (module realtime, ADR-011).
// Pas de notification push : rien à annoncer, seulement l'écran à tenir à jour.
@Injectable()
export class AppProfileCountersPublisher extends ProfileCountersPublisher {
  constructor(private readonly realtime: RealtimeService) {
    super();
  }

  countersChanged({ userId, followersCount, followingCount }: ProfileCounters): Promise<void> {
    return this.realtime.sendToUser(userId, { event: 'profileCountersChanged', data: { followersCount, followingCount } });
  }
}
