import { Injectable, Logger, OnApplicationBootstrap } from '@nestjs/common';
import { SubscriptionsService } from '../application/subscriptions.service';

// Reconstruit le registre des abonnés (Redis) depuis la base au démarrage de l'API (ADR-073), comme celui des comptes
// suspendus (ADR-037). Au démarrage seulement, jamais à la construction (l'export OpenAPI ne démarre rien).
@Injectable()
export class PlusMembersSync implements OnApplicationBootstrap {
  private readonly logger = new Logger('PlusMembers');

  constructor(private readonly subscriptions: SubscriptionsService) {}

  async onApplicationBootstrap(): Promise<void> {
    const count = await this.subscriptions.syncRegistry();
    this.logger.log(`Registre des abonnés Plus reconstruit : ${count} abonné(s)`);
  }
}
