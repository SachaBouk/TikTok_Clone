import { Global, Module } from '@nestjs/common';
import { RedisSuspendedAccounts } from './redis-suspended-accounts';
import { SuspendedAccounts } from './suspended-accounts';

// Registre des comptes suspendus (ADR-037), dans le Redis de l'API (RedisModule, global). Les modules injectent
// le port `SuspendedAccounts` dans leur service par la factory de leur module.
@Global()
@Module({
  providers: [{ provide: SuspendedAccounts, useClass: RedisSuspendedAccounts }],
  exports: [SuspendedAccounts],
})
export class SuspensionModule {}
