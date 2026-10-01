import type { AuthService } from '../../auth/application/auth.service';
import { CannotSuspendAdminError } from '../../auth/domain/auth.errors';
import type { InteractionsService } from '../../interactions/application/interactions.service';
import type { RealtimeService } from '../../realtime/application/realtime.service';
import type { CommentFilter } from '../../interactions/domain/interaction';
import { CommentNotFoundError } from '../../interactions/domain/interaction.errors';
import type { UsersService } from '../../users/application/users.service';
import type { User } from '../../users/domain/user';
import { UserNotFoundError } from '../../users/domain/user.errors';
import type { VideosService } from '../../videos/application/videos.service';
import type { VideoFilter } from '../../videos/domain/video';
import { VideoNotFoundError } from '../../videos/domain/video.errors';
import type { WalletService } from '../../wallet/application/wallet.service';
import type { LedgerFilter } from '../../wallet/domain/wallet';
import {
  type AdminAccount,
  type LedgerLine,
  type ModeratedComment,
  type ModeratedVideo,
  type Page,
  type PlatformStats,
  RECENT_PERIOD_DAYS,
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
    private readonly now: () => Date = () => new Date(),
  ) {}

  async getStats(): Promise<PlatformStats> {
    const since = new Date(this.now().getTime() - RECENT_PERIOD_DAYS * 24 * 60 * 60 * 1000);
    const [usersTotal, usersRecent, usersSuspended, videos, commentsTotal, commentsRecent, tokens] = await Promise.all([
      this.users.countAccounts(),
      this.users.countAccounts(since),
      this.auth.countSuspended(),
      this.videos.countVideos(since),
      this.interactions.countComments(),
      this.interactions.countComments(since),
      this.wallet.getStats(since),
    ]);
    const { byStatus } = videos;
    return {
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

  async getAccount(userId: string): Promise<AdminAccount> {
    const [account] = await this.describeAccounts([await this.account(userId)]);
    return account!;
  }

  // Suspension (ADR-037) : les règles sont dans auth (motif obligatoire, pas d'administrateur, sessions révoquées) ;
  // ici, la fermeture des WebSocket du compte, que auth ne peut pas faire (realtime dépend de auth). Un compte déjà
  // suspendu garde sa suspension. La personne n'est pas prévenue autrement qu'au moment où l'app se reconnecte.
  async suspendAccount(adminId: string, userId: string, reason: string): Promise<AdminAccount> {
    await this.account(userId);
    try {
      if (!(await this.auth.suspend(userId, adminId, reason))) throw new AdminTargetNotFoundError('Compte', userId);
    } catch (error) {
      if (error instanceof CannotSuspendAdminError) throw new AdminActionRefusedError(error.message);
      throw error;
    }
    await this.realtime.disconnectUser(userId);
    return this.getAccount(userId);
  }

  // Levée : le compte peut se reconnecter, ses contenus réapparaissent. Idempotent.
  async liftSuspension(userId: string): Promise<AdminAccount> {
    await this.account(userId);
    await this.auth.liftSuspension(userId);
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

  // Retrait par modération : même suppression que par l'auteur (cascade, nettoyage des fichiers).
  async removeVideo(videoId: string): Promise<void> {
    try {
      await this.videos.removeVideo(videoId);
    } catch (error) {
      if (error instanceof VideoNotFoundError) throw new AdminTargetNotFoundError('Vidéo', videoId);
      throw error;
    }
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

  async removeComment(commentId: string): Promise<void> {
    try {
      await this.interactions.removeComment(commentId);
    } catch (error) {
      if (error instanceof CommentNotFoundError) throw new AdminTargetNotFoundError('Commentaire', commentId);
      throw error;
    }
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
    const [adminIds, videoCounts, balances, suspensions] = await Promise.all([
      this.auth.findAdminIds(ids),
      this.videos.countVideosByAuthors(ids),
      this.wallet.getBalances(ids),
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
        suspension: suspension
          ? { suspendedAt: suspension.suspendedAt, reason: suspension.reason, suspendedBy: moderators.get(suspension.suspendedBy ?? '') ?? null }
          : null,
      };
    });
  }

  private async usersById(ids: string[]): Promise<Map<string, User>> {
    return new Map((await this.users.getByIds(ids)).map((user) => [user.id, user]));
  }
}
