import { Global, Module } from '@nestjs/common';
import { HostedVideos } from './hosted-videos';
import { MuxHostedVideos } from './mux-hosted-videos';
import { MuxConfig } from './mux.config';

// Mux Video (ADR-074), partagé par les modules `videos` et `stories` : configuration et port `HostedVideos`, injecté dans
// leur service par la factory de leur module. Le webhook de Mux est reçu par le module `mux` (`modules/mux`).
@Global()
@Module({
  providers: [
    { provide: MuxConfig, useFactory: () => MuxConfig.fromEnv() },
    { provide: HostedVideos, useFactory: (config: MuxConfig) => new MuxHostedVideos(config), inject: [MuxConfig] },
  ],
  exports: [MuxConfig, HostedVideos],
})
export class MuxModule {}
