import { Module } from '@nestjs/common';
import { UsersModule } from '../users/users.module';
import { CrossLiveService } from './application/crosslive.service';
import { ParticipantAccounts, ParticipantTokenSigner } from './domain/participant-token';
import { crossLiveConfigFromEnv } from './infrastructure/crosslive.config';
import { JoseParticipantTokenSigner } from './infrastructure/jose-participant-token-signer';
import { UsersParticipantAccounts } from './infrastructure/users-participant-accounts';
import { CrossLiveController } from './interfaces/crosslive.controller';

// Live commun d'echimine (ADR-079) : signe le Jeton de Participant du serveur commun `live.echimine.fr`. Aucune donnée
// propre : comptes lus par `users`. Aucun module n’en dépend. Remplacera le module `live` (ADR-053) une fois l'ADR accepté.
@Module({
  imports: [UsersModule],
  controllers: [CrossLiveController],
  providers: [
    { provide: ParticipantAccounts, useClass: UsersParticipantAccounts },
    { provide: ParticipantTokenSigner, useFactory: () => new JoseParticipantTokenSigner(crossLiveConfigFromEnv()) },
    {
      provide: CrossLiveService,
      useFactory: (accounts: ParticipantAccounts, signer: ParticipantTokenSigner) => new CrossLiveService(accounts, signer),
      inject: [ParticipantAccounts, ParticipantTokenSigner],
    },
  ],
})
export class CrossLiveModule {}
