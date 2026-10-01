import type { InteractionsService } from '../../interactions/application/interactions.service';
import { CommentNotFoundError } from '../../interactions/domain/interaction.errors';
import type { UsersService } from '../../users/application/users.service';
import { UserNotFoundError } from '../../users/domain/user.errors';
import type { VideosService } from '../../videos/application/videos.service';
import {
  MAX_REPORT_DETAILS_LENGTH,
  MAX_REPORTS_PER_TARGET,
  REPORT_RATE_LIMITS,
  type OpenReportTarget,
  type Report,
  type ReportReason,
  type ReportTarget,
} from '../domain/report';
import { CannotReportYourselfError, InvalidReportError, ReportTargetNotFoundError, TooManyReportsError } from '../domain/report.errors';
import type { ReportRepository } from '../domain/report.repository';
import type { RateLimiter } from '../../../rate-limit/rate-limiter';
import type { SuspendedAccounts } from '../../../suspension/suspended-accounts';

export interface ReportInput {
  target: ReportTarget;
  reason: ReportReason;
  details?: string | null;
}

export interface OpenReportTargetPage {
  items: OpenReportTarget[];
  nextCursor: string | null;
}

// Une cible et ses signalements ; `open` est nul si aucun n'est encore ouvert.
export interface ReportTargetDetail {
  target: ReportTarget;
  targetUserId: string;
  open: OpenReportTarget | null;
  reports: Report[];
}

// Service applicatif des signalements (ADR-038, ADR-003).
// - Une personne signale ce qu'elle voit : une vidéo publiée, un commentaire, un compte. Rien n'est masqué ensuite :
//   seul un administrateur décide.
// - Un seul signalement ouvert par personne et par cible ; un doublon ne change rien et ne compte pas dans la limite.
// - Une décision clôt tous les signalements ouverts d'une cible : contenu supprimé, compte suspendu (toutes ses
//   cibles), ou classement sans suite.
export class ReportsService {
  constructor(
    private readonly reports: ReportRepository,
    private readonly users: UsersService,
    private readonly videos: VideosService,
    private readonly interactions: InteractionsService,
    private readonly rateLimiter: RateLimiter,
    private readonly suspended: SuspendedAccounts,
    private readonly now: () => Date = () => new Date(),
  ) {}

  async report(reporterId: string, input: ReportInput): Promise<void> {
    const details = input.details?.trim() || null;
    if (details && details.length > MAX_REPORT_DETAILS_LENGTH) throw new InvalidReportError(`La précision fait au plus ${MAX_REPORT_DETAILS_LENGTH} caractères`);
    const { userId, excerpt } = await this.resolve(input.target);
    if (userId === reporterId) throw new CannotReportYourselfError();

    const key = `report:${reporterId}`;
    const retryAfter = await this.rateLimiter.check(key, REPORT_RATE_LIMITS);
    if (retryAfter) throw new TooManyReportsError(retryAfter);
    const created = await this.reports.create({ reporterId, target: input.target, targetUserId: userId, reason: input.reason, details, excerpt });
    if (created) await this.rateLimiter.hit(key, REPORT_RATE_LIMITS);
  }

  // File de modération : cibles avec des signalements ouverts, de la plus récemment signalée à la plus ancienne.
  async listOpenTargets(cursor: string | null, limit: number): Promise<OpenReportTargetPage> {
    const rows = await this.reports.listOpenTargets(cursor, limit + 1);
    const page = rows.slice(0, limit);
    return { items: page, nextCursor: rows.length > limit ? page.at(-1)!.latestId : null };
  }

  // Une cible et ses signalements (ouverts et clos) ; introuvable si elle n'a jamais été signalée.
  async getTarget(target: ReportTarget): Promise<ReportTargetDetail> {
    const [open, reports] = await Promise.all([this.reports.findOpenTarget(target), this.reports.listForTarget(target, MAX_REPORTS_PER_TARGET)]);
    if (reports.length === 0) throw new ReportTargetNotFoundError();
    return { target, targetUserId: reports[0]!.targetUserId, open, reports };
  }

  // Classement sans suite par un administrateur. Renvoie le nombre de signalements clos.
  dismiss(target: ReportTarget, adminId: string): Promise<number> {
    return this.reports.resolveTarget(target, 'dismissed', adminId, this.now());
  }

  // Le contenu signalé a été supprimé par un administrateur (module admin).
  contentRemoved(target: ReportTarget, adminId: string): Promise<number> {
    return this.reports.resolveTarget(target, 'contentRemoved', adminId, this.now());
  }

  // Le compte a été suspendu (ADR-037) : ses signalements ouverts, compte, vidéos et commentaires, sont clos.
  accountSuspended(userId: string, adminId: string): Promise<number> {
    return this.reports.resolveForUser(userId, 'accountSuspended', adminId, this.now());
  }

  countOpenTargets(): Promise<number> {
    return this.reports.countOpenTargets();
  }

  // Compte visé et texte à copier. Ce que la personne ne peut pas voir est introuvable : vidéo non publiée, commentaire
  // supprimé, contenu d'un compte suspendu, compte suspendu.
  private async resolve(target: ReportTarget): Promise<{ userId: string; excerpt: string | null }> {
    switch (target.type) {
      case 'video': {
        const [video] = await this.videos.getPublishedVideos([target.id]);
        if (!video) throw new ReportTargetNotFoundError();
        await this.assertNotSuspended(video.userId);
        return { userId: video.userId, excerpt: video.description };
      }
      case 'comment': {
        const comment = await this.interactions.getComment(target.id).catch((error: unknown) => {
          if (error instanceof CommentNotFoundError) throw new ReportTargetNotFoundError();
          throw error;
        });
        await this.assertNotSuspended(comment.userId);
        return { userId: comment.userId, excerpt: comment.content };
      }
      case 'account': {
        const user = await this.users.getById(target.id).catch((error: unknown) => {
          if (error instanceof UserNotFoundError) throw new ReportTargetNotFoundError();
          throw error;
        });
        await this.assertNotSuspended(user.id);
        return { userId: user.id, excerpt: null };
      }
    }
  }

  private async assertNotSuspended(userId: string): Promise<void> {
    if (await this.suspended.has(userId)) throw new ReportTargetNotFoundError();
  }
}
