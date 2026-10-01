import { Module } from '@nestjs/common';
import { RateLimiter } from '../../rate-limit/rate-limiter';
import { SuspendedAccounts } from '../../suspension/suspended-accounts';
import { InteractionsService } from '../interactions/application/interactions.service';
import { InteractionsModule } from '../interactions/interactions.module';
import { UsersService } from '../users/application/users.service';
import { UsersModule } from '../users/users.module';
import { VideosService } from '../videos/application/videos.service';
import { VideosModule } from '../videos/videos.module';
import { ReportsService } from './application/reports.service';
import { ReportRepository } from './domain/report.repository';
import { PrismaReportRepository } from './infrastructure/prisma-report.repository';
import { ReportsController } from './interfaces/reports.controller';

// Signalements (ADR-038), module ajouté à la liste de l'ADR-003. Cibles vérifiées via UsersService, VideosService et
// InteractionsService ; limite par le limiteur partagé (src/rate-limit) ; comptes suspendus par le registre partagé
// (src/suspension). Exporte ReportsService pour le module admin (file de modération).
@Module({
  imports: [UsersModule, VideosModule, InteractionsModule],
  controllers: [ReportsController],
  providers: [
    { provide: ReportRepository, useClass: PrismaReportRepository },
    {
      provide: ReportsService,
      useFactory: (
        reports: ReportRepository,
        users: UsersService,
        videos: VideosService,
        interactions: InteractionsService,
        rateLimiter: RateLimiter,
        suspended: SuspendedAccounts,
      ) => new ReportsService(reports, users, videos, interactions, rateLimiter, suspended),
      inject: [ReportRepository, UsersService, VideosService, InteractionsService, RateLimiter, SuspendedAccounts],
    },
  ],
  exports: [ReportsService],
})
export class ReportsModule {}
