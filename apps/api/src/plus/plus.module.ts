import { Global, Module } from '@nestjs/common';
import { PlusMembers } from './plus-members';
import { RedisPlusMembers } from './redis-plus-members';

// Registre des abonnés « Plus » (ADR-073), dans le Redis de l'API (RedisModule, global). Les modules injectent le port
// `PlusMembers` dans leur service par la factory de leur module.
@Global()
@Module({
  providers: [{ provide: PlusMembers, useClass: RedisPlusMembers }],
  exports: [PlusMembers],
})
export class PlusModule {}
