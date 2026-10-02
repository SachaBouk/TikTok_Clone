import type { InteractionsService } from '../../interactions/application/interactions.service';
import { CommentNotFoundError } from '../../interactions/domain/interaction.errors';
import type { MessagingService } from '../../messaging/application/messaging.service';
import { MessageNotFoundError } from '../../messaging/domain/messaging.errors';
import type { NotificationsService } from '../../notifications/application/notifications.service';
import type { UsersService } from '../../users/application/users.service';
import type { User } from '../../users/domain/user';
import { UserNotFoundError } from '../../users/domain/user.errors';
import type { VideosService } from '../../videos/application/videos.service';
import type { ModerationActionRepository } from '../domain/moderation-action.repository';
import {
  MAX_REPORT_DETAILS_LENGTH,
  MAX_REPORTS_PER_TARGET,
  REPORT_RATE_LIMITS,
  type ModerationAction,
  type ModerationActionType,
  type ModerationOutcome,
  type OpenReportTarget,
  type Report,
  type ReportReason,
  type ReportTarget,
  type ReportTargetType,
  type ResolvedReport,
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
  targetUserId: string | null;
  targetUsername: string;
  open: OpenReportTarget | null;
  reports: Report[];
}

// Contenu retiré par un administrateur.
export interface ContentRemoval {
  adminId: string;
  target: ReportTarget;
  // Auteur du contenu, prévenu avec le motif.
  authorId: string;
  // Texte du contenu, copié dans la notification et le journal.
  excerpt: string | null;
  reason: ReportReason;
}

export interface ModerationActionPage {
  items: ModerationAction[];
  nextCursor: string | null;
}

const REMOVAL_ACTIONS: Record<ReportTargetType, ModerationActionType> = {
  video: 'videoRemoved',
  comment: 'commentRemoved',
  message: 'messageRemoved',
  // Un compte ne se « retire » pas : il se suspend (voir `accountSuspended`).
  account: 'accountSuspended',
};

// Service applicatif des signalements et de la modération (ADR-038, ADR-003).
// - Une personne signale ce qu'elle voit : une vidéo publiée, un commentaire, un compte, un message reçu. Rien n'est
//   masqué ensuite : seul un administrateur décide.
// - Un seul signalement ouvert par personne et par cible ; un doublon ne change rien et ne compte pas dans la limite.
// - Une décision d'administrateur clôt les signalements ouverts concernés, prévient les personnes qui les ont envoyés
//   (centre d'activité et push), prévient l'auteur d'un contenu retiré (avec le motif) et s'inscrit au journal.
// - Une cible qui disparaît sans décision (contenu supprimé par son auteur, compte supprimé) voit ses signalements
//   clos par la base (triggers) ; ils restent dans l'historique, sans notification.
export class ReportsService {
  constructor(
    private readonly reports: ReportRepository,
    private readonly actions: ModerationActionRepository,
    private readonly users: UsersService,
    private readonly videos: VideosService,
    private readonly interactions: InteractionsService,
    private readonly messaging: MessagingService,
    private readonly notifications: NotificationsService,
    private readonly rateLimiter: RateLimiter,
    private readonly suspended: SuspendedAccounts,
    private readonly now: () => Date = () => new Date(),
  ) {}

  async report(reporterId: string, input: ReportInput): Promise<void> {
    const details = input.details?.trim() || null;
    if (details && details.length > MAX_REPORT_DETAILS_LENGTH)
      throw new InvalidReportError(`La précision fait au plus ${MAX_REPORT_DETAILS_LENGTH} caractères`);
    const { userId, excerpt } = await this.resolve(reporterId, input.target);
    if (userId === reporterId) throw new CannotReportYourselfError();
    const targetUser = await this.users.getById(userId).catch((error: unknown) => {
      if (error instanceof UserNotFoundError) throw new ReportTargetNotFoundError();
      throw error;
    });

    const key = `report:${reporterId}`;
    const retryAfter = await this.rateLimiter.check(key, REPORT_RATE_LIMITS);
    if (retryAfter) throw new TooManyReportsError(retryAfter);
    const created = await this.reports.create({
      reporterId,
      target: input.target,
      targetUserId: userId,
      targetUsername: targetUser.username,
      reason: input.reason,
      details,
      excerpt,
    });
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
    return { target, targetUserId: reports[0].targetUserId, targetUsername: reports[0].targetUsername, open, reports };
  }

  // Contenu retiré par un administrateur : signalements ouverts clos d'abord (les triggers les cloraient sinon comme
  // « supprimé par son auteur »), suppression par `remove`, puis l'auteur est prévenu avec le motif, les personnes qui
  // ont signalé reçoivent la décision, et l'action est journalisée. Si `remove` échoue, rien n'est annoncé.
  async removeContent(removal: ContentRemoval, remove: () => Promise<void>): Promise<void> {
    const resolved = await this.reports.resolveTarget(removal.target, 'contentRemoved', removal.adminId, this.now());
    await remove();
    await this.notifications.notifyModeration({
      type: 'contentRemoved',
      recipientId: removal.authorId,
      targetType: removal.target.type,
      reason: removal.reason,
      excerpt: removal.excerpt,
    });
    await this.announce(resolved, 'contentRemoved');
    await this.log(removal.adminId, REMOVAL_ACTIONS[removal.target.type], removal.target, removal.authorId, {
      reason: removal.reason,
      excerpt: removal.excerpt,
      reportsClosed: resolved.length,
    });
  }

  // Compte suspendu (ADR-037) : ses signalements ouverts (compte, vidéos, commentaires, messages) sont clos.
  async accountSuspended(userId: string, adminId: string, note: string): Promise<void> {
    const resolved = await this.reports.resolveForUser(userId, 'accountSuspended', adminId, this.now());
    await this.announce(resolved, 'accountSuspended');
    await this.log(adminId, 'accountSuspended', { type: 'account', id: userId }, userId, { note, reportsClosed: resolved.length });
  }

  async suspensionLifted(userId: string, adminId: string): Promise<void> {
    await this.log(adminId, 'suspensionLifted', { type: 'account', id: userId }, userId, {});
  }

  // Classement sans suite : le contenu reste en ligne. Renvoie le nombre de signalements clos (0 : rien d'ouvert,
  // rien n'est annoncé ni journalisé).
  async dismiss(target: ReportTarget, adminId: string): Promise<number> {
    const resolved = await this.reports.resolveTarget(target, 'dismissed', adminId, this.now());
    if (resolved.length === 0) return 0;
    await this.announce(resolved, 'dismissed');
    await this.log(adminId, 'reportsDismissed', target, resolved[0].targetUserId, { excerpt: resolved[0].excerpt, reportsClosed: resolved.length });
    return resolved.length;
  }

  countOpenTargets(): Promise<number> {
    return this.reports.countOpenTargets();
  }

  // Journal de modération, du plus récent au plus ancien ; `targetUserId` : actions sur ce compte.
  async listActions(filter: { targetUserId?: string }, cursor: string | null, limit: number): Promise<ModerationActionPage> {
    const rows = await this.actions.list(filter, cursor, limit + 1);
    const page = rows.slice(0, limit);
    return { items: page, nextCursor: rows.length > limit ? page.at(-1)!.id : null };
  }

  // Une notification « signalement examiné » par personne et par cible (plusieurs signalements de la même personne sur
  // la même cible ne sont pas possibles, mais une suspension clôt plusieurs cibles).
  private async announce(resolved: ResolvedReport[], outcome: ModerationOutcome): Promise<void> {
    const seen = new Set<string>();
    for (const report of resolved) {
      if (!report.reporterId) continue;
      const key = `${report.reporterId}:${report.target.type}:${report.target.id}`;
      if (seen.has(key)) continue;
      seen.add(key);
      await this.notifications.notifyModeration({
        type: 'reportResolved',
        recipientId: report.reporterId,
        targetType: report.target.type,
        outcome,
        excerpt: report.excerpt,
      });
    }
  }

  private async log(
    adminId: string,
    action: ModerationActionType,
    target: ReportTarget,
    targetUserId: string | null,
    details: { reason?: ReportReason; note?: string; excerpt?: string | null; reportsClosed?: number },
  ): Promise<void> {
    const users = new Map((await this.users.getByIds([adminId, ...(targetUserId ? [targetUserId] : [])])).map((u: User) => [u.id, u]));
    await this.actions.add({
      adminId,
      adminUsername: users.get(adminId)?.username ?? '',
      action,
      target,
      targetUserId,
      targetUsername: (targetUserId && users.get(targetUserId)?.username) || null,
      reason: details.reason ?? null,
      note: details.note ?? null,
      excerpt: details.excerpt ?? null,
      reportsClosed: details.reportsClosed ?? 0,
    });
  }

  // Compte visé et texte à copier. Ce que la personne ne peut pas voir est introuvable : vidéo non publiée, commentaire
  // supprimé, message hors de ses conversations, contenu d'un compte suspendu, compte suspendu.
  private async resolve(reporterId: string, target: ReportTarget): Promise<{ userId: string; excerpt: string | null }> {
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
      case 'message': {
        const message = await this.messaging.getVisibleMessage(reporterId, target.id).catch((error: unknown) => {
          if (error instanceof MessageNotFoundError) throw new ReportTargetNotFoundError();
          throw error;
        });
        await this.assertNotSuspended(message.senderId);
        // Seul le message signalé est copié, jamais le reste de la conversation.
        return { userId: message.senderId, excerpt: message.content || (message.sharedVideoId ? 'Vidéo partagée' : null) };
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
