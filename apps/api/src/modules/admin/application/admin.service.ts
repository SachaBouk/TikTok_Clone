import type { AuthService } from '../../auth/application/auth.service';
import { CannotSuspendAdminError } from '../../auth/domain/auth.errors';
import type { InteractionsService } from '../../interactions/application/interactions.service';
import type { LiveService } from '../../live/application/live.service';
import type { StoriesService } from '../../stories/application/stories.service';
import { StoryNotFoundError } from '../../stories/domain/story.errors';
import type { MessagingService } from '../../messaging/application/messaging.service';
import { MessageNotFoundError } from '../../messaging/domain/messaging.errors';
import type { RealtimeService } from '../../realtime/application/realtime.service';
import type { ReportsService } from '../../reports/application/reports.service';
import type { ModerationAction, OpenReportTarget, ReportReason, ReportTarget } from '../../reports/domain/report';
import { ReportTargetNotFoundError } from '../../reports/domain/report.errors';
import type { CommentFilter } from '../../interactions/domain/interaction';
import { CommentNotFoundError } from '../../interactions/domain/interaction.errors';
import type { UsersService } from '../../users/application/users.service';
import type { User } from '../../users/domain/user';
import { UserNotFoundError } from '../../users/domain/user.errors';
import type { VideosService } from '../../videos/application/videos.service';
import type { VideoFilter } from '../../videos/domain/video';
import { VideoNotFoundError } from '../../videos/domain/video.errors';
import type { GiftPage, WalletService } from '../../wallet/application/wallet.service';
import type { LedgerFilter } from '../../wallet/domain/wallet';
import {
  type AdminAccount,
  type LedgerLine,
  type ModeratedComment,
  type ModeratedReportTarget,
  type ModeratedVideo,
  type Page,
  type PlatformStats,
  RECENT_PERIOD_DAYS,
  type ReportTargetDetail,
} from '../domain/admin';
import { AdminActionRefusedError, AdminTargetNotFoundError } from '../domain/admin.errors';

// Service applicatif du backoffice (ADR-004). Sans données propres : il lit et modère via les services
// exportés des autres modules (ADR-003), qui portent les règles (suppression d'une vidéo, cascade…).
// L'accès est contrôlé en amont par @AdminOnly() (rôle relu en base à chaque requête).
export class AdminService {
  constructor(
    private readonly users: UsersService,
    private readonly videos: VideosService,
    private readonly interactions: InteractionsService,
    private readonly auth: AuthService,
    private readonly wallet: WalletService,
    private readonly realtime: RealtimeService,
    private readonly reports: ReportsService,
    private readonly messaging: MessagingService,
    private readonly stories: StoriesService,
    private readonly lives: LiveService,
    private readonly now: () => Date = () => new Date(),
  ) {}

  async getStats(): Promise<PlatformStats> {
    const since = new Date(this.now().getTime() - RECENT_PERIOD_DAYS * 24 * 60 * 60 * 1000);
    const [usersTotal, usersRecent, usersSuspended, videos, commentsTotal, commentsRecent, tokens, openReportTargets] = await Promise.all([
      this.users.countAccounts(),
      this.users.countAccounts(since),
      this.auth.countSuspended(),
      this.videos.countVideos(since),
      this.interactions.countComments(),
      this.interactions.countComments(since),
      this.wallet.getStats(since),
      this.reports.countOpenTargets(),
    ]);
    const { byStatus } = videos;
    return {
      reports: { openTargets: openReportTargets },
      users: { total: usersTotal, last7Days: usersRecent, suspended: usersSuspended },
      videos: {
        total: byStatus.uploading + byStatus.processing + byStatus.ready + byStatus.failed,
        last7Days: videos.createdSince,
        ...byStatus,
      },
      comments: { total: commentsTotal, last7Days: commentsRecent },
      tokens,
    };
  }

  // Recherche par pseudo, nom ou identifiant ; sans recherche, tous les comptes.
  async listAccounts(query: string | null, cursor: string | null, limit: number): Promise<Page<AdminAccount>> {
    const rows = await this.users.searchAccounts(query, cursor, limit + 1);
    const page = rows.slice(0, limit);
    return { items: await this.describeAccounts(page), nextCursor: rows.length > limit ? page.at(-1)!.id : null };
  }

  // Comptes suspendus (ADR-037), du plus récemment suspendu au plus ancien. Curseur : identifiant du dernier compte lu,
  // même s'il a été sauté (supprimé entre les deux lectures) ; une page vide si sa suspension a été levée depuis.
  async listSuspendedAccounts(cursor: string | null, limit: number): Promise<Page<AdminAccount>> {
    const ids = await this.auth.listSuspended(cursor, limit + 1);
    const page = ids.slice(0, limit);
    const users = await this.usersById(page);
    const ordered = page.flatMap((id) => users.get(id) ?? []);
    return { items: await this.describeAccounts(ordered), nextCursor: ids.length > limit ? page.at(-1)! : null };
  }

  async getAccount(userId: string): Promise<AdminAccount> {
    const [account] = await this.describeAccounts([await this.account(userId)]);
    return account;
  }

  // Suspension (ADR-037) : les règles sont dans auth (motif obligatoire, pas d'administrateur, sessions révoquées) ;
  // ici, la fermeture des WebSocket du compte, que auth ne peut pas faire (realtime dépend de auth). Un compte déjà
  // suspendu garde sa suspension (rien n'est alors journalisé). La personne l'apprend à la connexion.
  async suspendAccount(adminId: string, userId: string, reason: string): Promise<AdminAccount> {
    await this.account(userId);
    const wasSuspended = (await this.auth.getSuspensions([userId])).has(userId);
    try {
      if (!(await this.auth.suspend(userId, adminId, reason))) throw new AdminTargetNotFoundError('Compte', userId);
    } catch (error) {
      if (error instanceof CannotSuspendAdminError) throw new AdminActionRefusedError(error.message);
      throw error;
    }
    await this.realtime.disconnectUser(userId);
    // Son live en cours s'arrête (ADR-053).
    await this.lives.endForSuspension(userId);
    // Ses signalements ouverts sont clos, les personnes qui ont signalé prévenues, l'action journalisée (ADR-038).
    if (!wasSuspended) await this.reports.accountSuspended(userId, adminId, reason.trim());
    return this.getAccount(userId);
  }

  // Levée : le compte peut se reconnecter, ses contenus réapparaissent. Idempotent (journalisée si elle a lieu).
  async liftSuspension(adminId: string, userId: string): Promise<AdminAccount> {
    await this.account(userId);
    const wasSuspended = (await this.auth.getSuspensions([userId])).has(userId);
    await this.auth.liftSuspension(userId);
    if (wasSuspended) await this.reports.suspensionLifted(userId, adminId);
    return this.getAccount(userId);
  }

  async listVideos(filter: VideoFilter, cursor: string | null, limit: number): Promise<Page<ModeratedVideo>> {
    const rows = await this.videos.listVideoDetails(filter, cursor, limit + 1);
    const page = rows.slice(0, limit);
    const authors = await this.usersById(page.map((video) => video.userId));
    return {
      // Un auteur supprimé entre les deux lectures : la vidéo part avec lui (cascade), on la saute.
      items: page.flatMap((video) => {
        const author = authors.get(video.userId);
        return author ? [{ video, author }] : [];
      }),
      nextCursor: rows.length > limit ? page.at(-1)!.id : null,
    };
  }

  async getVideo(videoId: string): Promise<ModeratedVideo> {
    const [video] = await this.videos.getVideoDetails([videoId]);
    const author = video && (await this.usersById([video.userId])).get(video.userId);
    if (!video || !author) throw new AdminTargetNotFoundError('Vidéo', videoId);
    return { video, author };
  }

  // Retrait par modération : même suppression que par l'auteur (cascade, nettoyage des fichiers). Motif obligatoire,
  // annoncé à l'auteur ; signalements ouverts clos et personnes qui ont signalé prévenues ; journalisé (ADR-038).
  async removeVideo(adminId: string, videoId: string, reason: ReportReason): Promise<void> {
    const [video] = await this.videos.getVideoDetails([videoId]);
    if (!video) throw new AdminTargetNotFoundError('Vidéo', videoId);
    await this.reports.removeContent(
      { adminId, target: { type: 'video', id: videoId }, authorId: video.userId, excerpt: video.description, reason },
      async () => {
        try {
          await this.videos.removeVideo(videoId);
        } catch (error) {
          if (error instanceof VideoNotFoundError) throw new AdminTargetNotFoundError('Vidéo', videoId);
          throw error;
        }
      },
    );
  }

  // Retrait d'un message (ADR-038), pour les deux participants, comme par son expéditeur. Seul ce message est vu par
  // l'administrateur (signalement), jamais le reste de la conversation.
  async removeMessage(adminId: string, messageId: string, reason: ReportReason): Promise<void> {
    const [message] = await this.messaging.getMessages([messageId]);
    if (!message) throw new AdminTargetNotFoundError('Message', messageId);
    await this.reports.removeContent(
      {
        adminId,
        target: { type: 'message', id: messageId },
        authorId: message.senderId,
        excerpt: message.content || (message.sharedVideoId ? 'Vidéo partagée' : null),
        reason,
      },
      async () => {
        try {
          await this.messaging.removeMessage(messageId);
        } catch (error) {
          if (error instanceof MessageNotFoundError) throw new AdminTargetNotFoundError('Message', messageId);
          throw error;
        }
      },
    );
  }

  // Retrait d'une story signalée (ADR-051), quel que soit son statut ; l'auteur est prévenu avec le motif.
  async removeStory(adminId: string, storyId: string, reason: ReportReason): Promise<void> {
    const [story] = await this.stories.getStoriesByIds([storyId]);
    if (!story) throw new AdminTargetNotFoundError('Story', storyId);
    await this.reports.removeContent({ adminId, target: { type: 'story', id: storyId }, authorId: story.userId, excerpt: null, reason }, async () => {
      try {
        await this.stories.removeStory(storyId);
      } catch (error) {
        if (error instanceof StoryNotFoundError) throw new AdminTargetNotFoundError('Story', storyId);
        throw error;
      }
    });
  }

  // Arrêt d'un live signalé (ADR-053) : l'auteur est prévenu avec le motif. Un live déjà terminé est introuvable.
  async removeLive(adminId: string, liveId: string, reason: ReportReason): Promise<void> {
    const [item] = await this.lives.getLivesByIds([liveId]);
    if (!item || item.live.status !== 'live') throw new AdminTargetNotFoundError('Live', liveId);
    await this.reports.removeContent(
      { adminId, target: { type: 'live', id: liveId }, authorId: item.live.userId, excerpt: item.live.title, reason },
      async () => {
        if (!(await this.lives.removeLive(liveId))) throw new AdminTargetNotFoundError('Live', liveId);
      },
    );
  }

  // Journal de modération (ADR-038), du plus récent au plus ancien ; `targetUserId` : actions sur ce compte.
  listModerationActions(filter: { targetUserId?: string }, cursor: string | null, limit: number): Promise<Page<ModerationAction>> {
    return this.reports.listActions(filter, cursor, limit);
  }

  // Journal des jetons, filtré par compte ou « à rapprocher », avec le compte crédité s'il existe encore.
  async listWalletTransactions(filter: LedgerFilter, cursor: string | null, limit: number): Promise<Page<LedgerLine>> {
    const page = await this.wallet.listLedger(filter, cursor, limit);
    const users = await this.usersById(page.items.flatMap((entry) => (entry.userId ? [entry.userId] : [])));
    return {
      items: page.items.map((entry) => ({ entry, user: (entry.userId && users.get(entry.userId)) || null })),
      nextCursor: page.nextCursor,
    };
  }

  // Journal des cadeaux (ADR-050) : tous, ou envoyés et reçus par `userId`, du plus récent au plus ancien.
  listGifts(filter: { userId?: string }, cursor: string | null, limit: number): Promise<GiftPage> {
    return this.wallet.listGifts(filter, cursor, limit);
  }

  async listComments(filter: CommentFilter, cursor: string | null, limit: number): Promise<Page<ModeratedComment>> {
    const rows = await this.interactions.listAllComments(filter, cursor, limit + 1);
    const page = rows.slice(0, limit);
    const [authors, videos] = await Promise.all([
      this.usersById(page.map((comment) => comment.userId)),
      this.videos.getVideoDetails(page.map((comment) => comment.videoId)),
    ]);
    const videosById = new Map(videos.map((video) => [video.id, video]));
    return {
      items: page.flatMap((comment) => {
        const author = authors.get(comment.userId);
        const video = videosById.get(comment.videoId);
        return author && video ? [{ comment, author, video }] : [];
      }),
      nextCursor: rows.length > limit ? page.at(-1)!.id : null,
    };
  }

  async removeComment(adminId: string, commentId: string, reason: ReportReason): Promise<void> {
    const [comment] = await this.interactions.getComments([commentId]);
    if (!comment) throw new AdminTargetNotFoundError('Commentaire', commentId);
    await this.reports.removeContent(
      { adminId, target: { type: 'comment', id: commentId }, authorId: comment.userId, excerpt: comment.content, reason },
      async () => {
        try {
          await this.interactions.removeComment(commentId);
        } catch (error) {
          if (error instanceof CommentNotFoundError) throw new AdminTargetNotFoundError('Commentaire', commentId);
          throw error;
        }
      },
    );
  }

  // File des signalements (ADR-038) : cibles avec des signalements ouverts, de la plus récemment signalée à la plus
  // ancienne. Une cible qui disparaît sans décision est close par la base (triggers) et quitte la file.
  async listReportTargets(cursor: string | null, limit: number): Promise<Page<ModeratedReportTarget>> {
    const page = await this.reports.listOpenTargets(cursor, limit);
    const rows = page.items.map((open) => ({ target: open.target, targetUserId: open.targetUserId, targetUsername: open.targetUsername, open }));
    return { items: await this.describeReportTargets(rows), nextCursor: page.nextCursor };
  }

  // Une cible et tous ses signalements (ouverts et clos), avec les comptes qui ont signalé et décidé.
  async getReportTarget(target: ReportTarget): Promise<ReportTargetDetail> {
    let detail;
    try {
      detail = await this.reports.getTarget(target);
    } catch (error) {
      if (error instanceof ReportTargetNotFoundError) throw new AdminTargetNotFoundError('Signalement', target.id);
      throw error;
    }
    const [described] = await this.describeReportTargets([
      { target, targetUserId: detail.targetUserId, targetUsername: detail.targetUsername, open: detail.open, latest: detail.reports[0] },
    ]);
    if (!described) throw new AdminTargetNotFoundError('Signalement', target.id);
    const users = await this.usersById(detail.reports.flatMap((r) => [r.reporterId, r.resolvedBy].filter((id): id is string => !!id)));
    return {
      target: described,
      reports: detail.reports.map((report) => ({
        report,
        reporter: (report.reporterId && users.get(report.reporterId)) || null,
        resolvedBy: (report.resolvedBy && users.get(report.resolvedBy)) || null,
      })),
    };
  }

  // Classement sans suite : les signalements ouverts de la cible sont clos, le contenu reste en ligne.
  async dismissReports(adminId: string, target: ReportTarget): Promise<void> {
    if ((await this.reports.dismiss(target, adminId)) === 0) throw new AdminTargetNotFoundError('Signalement', target.id);
  }

  // Compte visé supprimé depuis : son pseudo copié reste (signalements gardés, anonymisés).
  private async describeReportTargets(
    rows: {
      target: ReportTarget;
      targetUserId: string | null;
      targetUsername: string;
      open: OpenReportTarget | null;
      latest?: { excerpt: string | null; createdAt: Date };
    }[],
  ): Promise<ModeratedReportTarget[]> {
    const idsOf = (type: ReportTarget['type']) => rows.filter((r) => r.target.type === type).map((r) => r.target.id);
    const [users, videos, comments, messages, stories, lives] = await Promise.all([
      this.usersById(rows.flatMap((r) => (r.targetUserId ? [r.targetUserId] : []))),
      this.videos.getPublishedVideos(idsOf('video')),
      this.interactions.getComments(idsOf('comment')),
      this.messaging.getMessages(idsOf('message')),
      this.stories.getStoriesByIds(idsOf('story')),
      this.lives.getLivesByIds(idsOf('live')),
    ]);
    // Un live est disponible tant qu'il est en cours (pas de replay).
    const liveIds = new Set(lives.filter((item) => item.live.status === 'live').map((item) => item.live.id));
    // Une story expirée mais pas encore supprimée n'est plus disponible.
    const storiesById = new Map(stories.filter((s) => s.status === 'ready' && s.expiresAt && s.expiresAt > this.now()).map((s) => [s.id, s]));
    const videosById = new Map(videos.map((v) => [v.id, v]));
    const commentsById = new Map(comments.map((c) => [c.id, c]));
    const messageIds = new Set(messages.map((m) => m.id));
    return rows.map(({ target, targetUserId, targetUsername, open, latest }) => {
      const targetUser = (targetUserId && users.get(targetUserId)) || null;
      const video = target.type === 'video' ? videosById.get(target.id) : undefined;
      const comment = target.type === 'comment' ? commentsById.get(target.id) : undefined;
      const story = target.type === 'story' ? storiesById.get(target.id) : undefined;
      const available =
        target.type === 'account'
          ? !!targetUser
          : target.type === 'message'
            ? messageIds.has(target.id)
            : target.type === 'live'
              ? liveIds.has(target.id)
              : !!video || !!comment || !!story;
      return {
        target,
        targetUser,
        targetUsername,
        available,
        thumbnailUrl: video?.thumbnailUrl ?? story?.thumbnailUrl ?? null,
        videoId: comment?.videoId ?? null,
        story: story?.mediaUrl ? { mediaType: story.mediaType, mediaUrl: story.mediaUrl } : null,
        open,
        excerpt: open?.excerpt ?? latest?.excerpt ?? null,
        latestAt: open?.latestAt ?? latest?.createdAt ?? this.now(),
      };
    });
  }

  private async account(userId: string): Promise<User> {
    try {
      return await this.users.getById(userId);
    } catch (error) {
      if (error instanceof UserNotFoundError) throw new AdminTargetNotFoundError('Compte', userId);
      throw error;
    }
  }

  private async describeAccounts(users: User[]): Promise<AdminAccount[]> {
    const ids = users.map((user) => user.id);
    const [adminIds, videoCounts, balances, earnings, suspensions] = await Promise.all([
      this.auth.findAdminIds(ids),
      this.videos.countVideosByAuthors(ids),
      this.wallet.getBalances(ids),
      this.wallet.getEarnings(ids),
      this.auth.getSuspensions(ids),
    ]);
    const moderators = await this.usersById([...suspensions.values()].flatMap((s) => (s.suspendedBy ? [s.suspendedBy] : [])));
    return users.map((user) => {
      const suspension = suspensions.get(user.id);
      return {
        user,
        isAdmin: adminIds.has(user.id),
        videosCount: videoCounts.get(user.id) ?? 0,
        tokenBalance: balances.get(user.id) ?? 0,
        tokenEarned: earnings.get(user.id) ?? 0,
        suspension: suspension
          ? { suspendedAt: suspension.suspendedAt, reason: suspension.reason, suspendedBy: moderators.get(suspension.suspendedBy ?? '') ?? null }
          : null,
      };
    });
  }

  // Comptes existants parmi `ids` (journal de modération : administrateurs et comptes visés).
  usersByIds(ids: string[]): Promise<Map<string, User>> {
    return this.usersById(ids);
  }

  private async usersById(ids: string[]): Promise<Map<string, User>> {
    return new Map((await this.users.getByIds(ids)).map((user) => [user.id, user]));
  }
}
