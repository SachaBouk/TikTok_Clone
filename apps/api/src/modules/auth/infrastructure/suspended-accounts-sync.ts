import { Injectable, Logger, OnApplicationBootstrap } from '@nestjs/common';
import { AuthService } from '../application/auth.service';

// Reconstruit le registre des comptes suspendus (Redis) depuis la base au démarrage de l'API (ADR-037) : un Redis
// vidé ou une suspension écrite pendant une panne de Redis sont rattrapés. Au démarrage seulement, jamais à la
// construction (l'export OpenAPI construit les modules sans les démarrer).
@Injectable()
export class SuspendedAccountsSync implements OnApplicationBootstrap {
  private readonly logger = new Logger('SuspendedAccounts');

  constructor(private readonly auth: AuthService) {}

  async onApplicationBootstrap(): Promise<void> {
    const count = await this.auth.syncSuspendedAccounts();
    this.logger.log(`Registre des comptes suspendus reconstruit : ${count} compte(s)`);
  }
}
