import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import type {
  AdminCommentDto,
  AdminCommentPageDto,
  AdminCommentVideoDto,
  AdminCountDto,
  AdminModerationActionDto,
  AdminModerationActionPageDto,
  AdminReportCountsDto,
  AdminReportDto,
  AdminReportReasonCountDto,
  AdminReportTargetDetailDto,
  StoryMediaType,
  AdminReportTargetDto,
  AdminReportTargetPageDto,
  AdminStatsDto,
  AdminSuspensionDto,
  AdminTokenStatsDto,
  AdminTokenTotalsDto,
  AdminUserCountsDto,
  AdminUserDto,
  AdminUserPageDto,
  AdminVideoCountsDto,
  AdminVideoDto,
  AdminVideoPageDto,
  AdminWalletTransactionDto,
  AdminWalletTransactionPageDto,
  ModerationActionType,
  ReportReason,
  ReportResolution,
  ReportTargetType,
  UserRole,
  VideoStatus,
  WalletTransactionKind,
  AdminGiftDto,
  AdminGiftPageDto,
  VideoVisibility,
} from '@repo/shared';
import type { User } from '../../users/domain/user';
import { VIDEO_VISIBILITIES } from '../../videos/domain/video';
import { toUserSummary, UserSummaryResponse } from '../../users/interfaces/user-summary.response';
import type { GiftWithContext } from '../../wallet/application/wallet.service';
import { WALLET_HISTORY_KINDS } from '../../wallet/domain/wallet';
import { GiftResponse, GiftVideoResponse, toGiftDto } from '../../wallet/interfaces/wallet.responses';
import type {
  AdminAccount,
  LedgerLine,
  ModeratedComment,
  ModeratedReport,
  ModeratedReportTarget,
  ModeratedVideo,
  PlatformStats,
  ReportTargetDetail,
} from '../domain/admin';
import { MODERATION_ACTION_TYPES, REPORT_REASONS, REPORT_RESOLUTIONS, REPORT_TARGET_TYPES, type ModerationAction } from '../../reports/domain/report';

// Schémas OpenAPI des DTO partagés : `implements` garantit à la compilation que chaque classe suit son type.

const VIDEO_STATUS = { enum: ['uploading', 'processing', 'ready', 'failed'], enumName: 'VideoStatus' };
const NEXT_CURSOR = { type: String, nullable: true, description: 'À renvoyer tel quel pour la page suivante ; null s’il n’y en a plus.' };

export class AdminSuspensionResponse implements AdminSuspensionDto {
  @ApiProperty({ format: 'date-time' })
  suspendedAt!: string;

  @ApiProperty({ description: 'Motif interne, saisi par l’administrateur.' })
  reason!: string;

  @ApiPropertyOptional({ type: UserSummaryResponse })
  suspendedBy?: UserSummaryResponse;
}

export class AdminUserResponse implements AdminUserDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty()
  username!: string;

  @ApiProperty()
  displayName!: string;

  @ApiProperty({ type: String, nullable: true, format: 'uri' })
  avatarUrl!: string | null;

  @ApiProperty({ type: String, nullable: true })
  bio!: string | null;

  // Attribué hors de l'API (`pnpm admin:grant`).
  @ApiProperty({ enum: ['user', 'admin'], enumName: 'UserRole' })
  role!: UserRole;

  @ApiProperty({ type: 'integer' })
  followersCount!: number;

  @ApiProperty({ type: 'integer' })
  followingCount!: number;

  @ApiProperty({ type: 'integer', description: 'Vidéos du compte, tous statuts confondus.' })
  videosCount!: number;

  @ApiProperty({ type: 'integer', minimum: 0, description: 'Solde de jetons.' })
  tokenBalance!: number;

  @ApiProperty({ type: 'integer', minimum: 0, description: 'Jetons reçus en cadeaux (ADR-050), non dépensables.' })
  tokenEarned!: number;

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;

  // Absente si le compte n'est pas suspendu (pas de description : voir CLAUDE.md, objet imbriqué facultatif).
  @ApiPropertyOptional({ type: AdminSuspensionResponse })
  suspension?: AdminSuspensionResponse;
}

export class AdminUserPageResponse implements AdminUserPageDto {
  @ApiProperty({ type: [AdminUserResponse], description: 'Du compte le plus récent au plus ancien.' })
  items!: AdminUserResponse[];

  @ApiProperty(NEXT_CURSOR)
  nextCursor!: string | null;
}

export class AdminVideoResponse implements AdminVideoDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty({ type: UserSummaryResponse })
  author!: UserSummaryResponse;

  @ApiProperty({ type: String, nullable: true })
  description!: string | null;

  @ApiProperty(VIDEO_STATUS)
  status!: VideoStatus;

  // Privée (ADR-061) : visible de son seul auteur dans l'app.
  @ApiProperty({ enum: VIDEO_VISIBILITIES, enumName: 'VideoVisibility' })
  visibility!: VideoVisibility;

  @ApiProperty({ description: 'Commentaires autorisés (ADR-062).' })
  commentsEnabled!: boolean;

  @ApiProperty({ type: String, nullable: true, format: 'uri', description: 'Manifeste HLS, quand la vidéo est `ready`.' })
  hlsUrl!: string | null;

  @ApiProperty({ type: String, nullable: true, format: 'uri' })
  thumbnailUrl!: string | null;

  @ApiProperty({ type: 'integer' })
  viewsCount!: number;

  @ApiProperty({ type: 'integer' })
  likesCount!: number;

  @ApiProperty({ type: 'integer' })
  commentsCount!: number;

  @ApiProperty({ type: 'integer' })
  favoritesCount!: number;

  @ApiProperty({ type: 'integer' })
  repostsCount!: number;

  @ApiProperty({ type: 'integer' })
  sharesCount!: number;

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;
}

export class AdminVideoPageResponse implements AdminVideoPageDto {
  @ApiProperty({ type: [AdminVideoResponse], description: 'De la vidéo la plus récente à la plus ancienne.' })
  items!: AdminVideoResponse[];

  @ApiProperty(NEXT_CURSOR)
  nextCursor!: string | null;
}

export class AdminCommentVideoResponse implements AdminCommentVideoDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty(VIDEO_STATUS)
  status!: VideoStatus;

  @ApiProperty({ type: String, nullable: true, format: 'uri' })
  thumbnailUrl!: string | null;
}

export class AdminCommentResponse implements AdminCommentDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty()
  content!: string;

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;

  @ApiProperty({ type: UserSummaryResponse })
  author!: UserSummaryResponse;

  @ApiProperty({ type: AdminCommentVideoResponse })
  video!: AdminCommentVideoResponse;
}

export class AdminCommentPageResponse implements AdminCommentPageDto {
  @ApiProperty({ type: [AdminCommentResponse], description: 'Du commentaire le plus récent au plus ancien.' })
  items!: AdminCommentResponse[];

  @ApiProperty(NEXT_CURSOR)
  nextCursor!: string | null;
}

export class AdminCountResponse implements AdminCountDto {
  @ApiProperty({ type: 'integer' })
  total!: number;

  @ApiProperty({ type: 'integer', description: 'Créés sur les 7 derniers jours.' })
  last7Days!: number;
}

export class AdminVideoCountsResponse extends AdminCountResponse implements AdminVideoCountsDto {
  @ApiProperty({ type: 'integer' })
  uploading!: number;

  @ApiProperty({ type: 'integer' })
  processing!: number;

  @ApiProperty({ type: 'integer' })
  ready!: number;

  @ApiProperty({ type: 'integer' })
  failed!: number;
}

export class AdminTokenTotalsResponse implements AdminTokenTotalsDto {
  @ApiProperty({ type: 'integer', description: 'Jetons vendus, clients inconnus compris.' })
  purchased!: number;

  @ApiProperty({ type: 'integer', description: 'Jetons remboursés (annoncés par le store).' })
  refunded!: number;

  @ApiProperty({ type: 'integer', description: 'Ajustements nets depuis le tableau de bord RevenueCat.' })
  adjusted!: number;
}

// Sans description sur les objets imbriqués : elle produirait un `allOf` (voir CLAUDE.md).
export class AdminTokenStatsResponse implements AdminTokenStatsDto {
  @ApiProperty({ type: AdminTokenTotalsResponse })
  production!: AdminTokenTotalsResponse;

  // Achats de test (Xcode, TestFlight, Test Store).
  @ApiProperty({ type: AdminTokenTotalsResponse })
  sandbox!: AdminTokenTotalsResponse;

  @ApiProperty({ type: 'integer', description: 'Jetons vendus en production sur les 7 derniers jours.' })
  purchasedLast7Days!: number;

  @ApiProperty({ type: 'integer', description: 'Somme des soldes des comptes.' })
  inCirculation!: number;

  @ApiProperty({ type: 'integer', description: 'Mouvements d’un client inconnu de l’API, à rapprocher.' })
  unmatched!: number;

  @ApiProperty({ type: 'integer', description: 'Jetons dépensés en cadeaux.' })
  giftsSpent!: number;

  @ApiProperty({ type: 'integer', description: 'Jetons dépensés en cadeaux sur les 7 derniers jours.' })
  giftsSpentLast7Days!: number;

  @ApiProperty({ type: 'integer', description: 'Gains (jetons reçus en cadeaux) des comptes existants.' })
  earned!: number;
}

export class AdminUserCountsResponse extends AdminCountResponse implements AdminUserCountsDto {
  @ApiProperty({ type: 'integer', description: 'Comptes suspendus en ce moment.' })
  suspended!: number;
}

export class AdminReportCountsResponse implements AdminReportCountsDto {
  @ApiProperty({ type: 'integer', description: 'Cibles avec au moins un signalement ouvert.' })
  openTargets!: number;
}

export class AdminStatsResponse implements AdminStatsDto {
  @ApiProperty({ type: AdminReportCountsResponse })
  reports!: AdminReportCountsResponse;

  @ApiProperty({ type: AdminUserCountsResponse })
  users!: AdminUserCountsResponse;

  @ApiProperty({ type: AdminVideoCountsResponse })
  videos!: AdminVideoCountsResponse;

  @ApiProperty({ type: AdminCountResponse })
  comments!: AdminCountResponse;

  @ApiProperty({ type: AdminTokenStatsResponse })
  tokens!: AdminTokenStatsResponse;
}

export class AdminWalletTransactionResponse implements AdminWalletTransactionDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  // Absent : compte supprimé depuis, ou client inconnu (`unmatched`).
  @ApiPropertyOptional({ type: UserSummaryResponse })
  user?: UserSummaryResponse;

  // Enum nommé partagé avec l'historique de l'app (le journal RevenueCat n'a jamais `giftSent`).
  @ApiProperty({ enum: WALLET_HISTORY_KINDS, enumName: 'WalletTransactionKind' })
  kind!: WalletTransactionKind;

  @ApiProperty({ type: 'integer', description: 'Mouvement annoncé par RevenueCat.' })
  amount!: number;

  @ApiProperty({ type: 'integer', description: 'Mouvement appliqué au solde (plancher à 0 ; 0 pour un client inconnu).' })
  appliedAmount!: number;

  @ApiProperty({ type: 'integer', nullable: true, description: 'Solde après le mouvement ; null pour un client inconnu.' })
  balanceAfter!: number | null;

  @ApiProperty({ description: 'Client inconnu de l’API au moment du webhook : aucun solde touché, à rapprocher.' })
  unmatched!: boolean;

  @ApiProperty()
  revenuecatEventId!: string;

  @ApiProperty({ description: 'Identifiant du client chez RevenueCat.' })
  appUserId!: string;

  @ApiProperty({ type: String, nullable: true })
  productId!: string | null;

  @ApiProperty({ type: String, nullable: true })
  storeTransactionId!: string | null;

  @ApiProperty({ type: String, nullable: true, example: 'APP_STORE' })
  store!: string | null;

  @ApiProperty({ example: 'PRODUCTION', description: 'PRODUCTION ou SANDBOX.' })
  environment!: string;

  @ApiProperty({ format: 'date-time' })
  occurredAt!: string;
}

export class AdminWalletTransactionPageResponse implements AdminWalletTransactionPageDto {
  @ApiProperty({ type: [AdminWalletTransactionResponse], description: 'Du mouvement le plus récent au plus ancien.' })
  items!: AdminWalletTransactionResponse[];

  @ApiProperty(NEXT_CURSOR)
  nextCursor!: string | null;
}

// Journal des cadeaux (ADR-050).
export class AdminGiftResponse implements AdminGiftDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty({ type: GiftResponse })
  gift!: GiftResponse;

  @ApiProperty({ type: 'integer', minimum: 1, description: 'Prix payé, en jetons.' })
  amount!: number;

  @ApiProperty({ type: 'integer', minimum: 0, description: 'Solde de l’expéditeur après le débit.' })
  senderBalanceAfter!: number;

  // Absent : compte supprimé depuis.
  @ApiPropertyOptional({ type: UserSummaryResponse })
  sender?: UserSummaryResponse;

  @ApiPropertyOptional({ type: UserSummaryResponse })
  recipient?: UserSummaryResponse;

  // Absente si elle n'est plus publiée.
  @ApiPropertyOptional({ type: GiftVideoResponse })
  video?: GiftVideoResponse;

  @ApiProperty({ type: String, format: 'uuid', nullable: true, description: 'Nul si la vidéo a été supprimée.' })
  videoId!: string | null;

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;
}

export class AdminGiftPageResponse implements AdminGiftPageDto {
  @ApiProperty({ type: [AdminGiftResponse], description: 'Du plus récent au plus ancien.' })
  items!: AdminGiftResponse[];

  @ApiProperty({ type: String, nullable: true })
  nextCursor!: string | null;
}

// Mappings explicites, champ par champ : rien n'est exposé par accident (clés de stockage, etc.).

export function toAdminUserDto({ user, isAdmin, videosCount, tokenBalance, tokenEarned, suspension }: AdminAccount): AdminUserDto {
  return {
    id: user.id,
    username: user.username,
    displayName: user.displayName,
    avatarUrl: user.avatarUrl,
    bio: user.bio,
    role: isAdmin ? 'admin' : 'user',
    followersCount: user.followersCount,
    followingCount: user.followingCount,
    videosCount,
    tokenBalance,
    tokenEarned,
    createdAt: user.createdAt.toISOString(),
    ...(suspension
      ? {
          suspension: {
            suspendedAt: suspension.suspendedAt.toISOString(),
            reason: suspension.reason,
            ...(suspension.suspendedBy ? { suspendedBy: toUserSummary(suspension.suspendedBy) } : {}),
          },
        }
      : {}),
  };
}

export function toAdminWalletTransactionDto({ entry, user }: LedgerLine): AdminWalletTransactionDto {
  return {
    id: entry.id,
    ...(user ? { user: toUserSummary(user) } : {}),
    kind: entry.kind,
    amount: entry.amount,
    appliedAmount: entry.appliedAmount,
    balanceAfter: entry.balanceAfter,
    unmatched: entry.unmatched,
    revenuecatEventId: entry.revenuecatEventId,
    appUserId: entry.appUserId,
    productId: entry.productId,
    storeTransactionId: entry.storeTransactionId,
    store: entry.store,
    environment: entry.environment,
    occurredAt: entry.occurredAt.toISOString(),
  };
}

export function toAdminVideoDto({ video, author }: ModeratedVideo): AdminVideoDto {
  return {
    id: video.id,
    author: toUserSummary(author),
    description: video.description,
    status: video.status,
    visibility: video.visibility,
    commentsEnabled: video.commentsEnabled,
    hlsUrl: video.hlsUrl,
    thumbnailUrl: video.thumbnailUrl,
    viewsCount: video.viewsCount,
    likesCount: video.likesCount,
    commentsCount: video.commentsCount,
    favoritesCount: video.favoritesCount,
    repostsCount: video.repostsCount,
    sharesCount: video.sharesCount,
    createdAt: video.createdAt.toISOString(),
  };
}

export function toAdminCommentDto({ comment, author, video }: ModeratedComment): AdminCommentDto {
  return {
    id: comment.id,
    content: comment.content,
    createdAt: comment.createdAt.toISOString(),
    author: toUserSummary(author),
    video: { id: video.id, status: video.status, thumbnailUrl: video.thumbnailUrl },
  };
}

export function toAdminStatsDto(stats: PlatformStats): AdminStatsDto {
  const { users, videos, comments, tokens } = stats;
  const totals = ({ purchased, refunded, adjusted }: PlatformStats['tokens']['production']) => ({ purchased, refunded, adjusted });
  return {
    reports: { openTargets: stats.reports.openTargets },
    users: { total: users.total, last7Days: users.last7Days, suspended: users.suspended },
    videos: {
      total: videos.total,
      last7Days: videos.last7Days,
      uploading: videos.uploading,
      processing: videos.processing,
      ready: videos.ready,
      failed: videos.failed,
    },
    comments: { total: comments.total, last7Days: comments.last7Days },
    tokens: {
      production: totals(tokens.production),
      sandbox: totals(tokens.sandbox),
      purchasedLast7Days: tokens.purchasedSince,
      inCirculation: tokens.inCirculation,
      unmatched: tokens.unmatched,
      giftsSpent: tokens.gifts.spent,
      giftsSpentLast7Days: tokens.gifts.spentSince,
      earned: tokens.gifts.earned,
    },
  };
}

// ─── Signalements (ADR-038) ──────────────────────────────────────────────────

const REPORT_TARGET_TYPE = { enum: REPORT_TARGET_TYPES, enumName: 'ReportTargetType' };
const REPORT_REASON = { enum: REPORT_REASONS, enumName: 'ReportReason' };
const REPORT_RESOLUTION = { enum: REPORT_RESOLUTIONS, enumName: 'ReportResolution' };

export class AdminReportReasonCountResponse implements AdminReportReasonCountDto {
  @ApiProperty(REPORT_REASON)
  reason!: ReportReason;

  @ApiProperty({ type: 'integer', minimum: 1 })
  count!: number;
}

export class AdminReportTargetResponse implements AdminReportTargetDto {
  @ApiProperty(REPORT_TARGET_TYPE)
  targetType!: ReportTargetType;

  @ApiProperty({ format: 'uuid' })
  targetId!: string;

  // Auteur du contenu, ou le compte signalé ; absent s'il a été supprimé depuis.
  @ApiPropertyOptional({ type: UserSummaryResponse })
  targetUser?: UserSummaryResponse;

  @ApiProperty({ description: 'Pseudo du compte visé au moment du signalement.' })
  targetUsername!: string;

  @ApiProperty({ description: 'Faux si le contenu a disparu depuis.' })
  available!: boolean;

  @ApiPropertyOptional({ format: 'uri' })
  thumbnailUrl?: string;

  @ApiPropertyOptional({ format: 'uuid', description: 'Commentaire : vidéo commentée.' })
  videoId?: string;

  @ApiPropertyOptional({ format: 'uri', description: 'Story (ADR-051) : photo ou manifeste HLS, tant qu’elle est visible.' })
  storyMediaUrl?: string;

  @ApiPropertyOptional({ enum: ['video', 'photo'], enumName: 'StoryMediaType' })
  storyMediaType?: StoryMediaType;

  @ApiPropertyOptional({ description: 'Texte signalé, copié au moment du signalement le plus récent.' })
  excerpt?: string;

  @ApiProperty({ type: 'integer', minimum: 0, description: 'Signalements ouverts.' })
  openCount!: number;

  @ApiProperty({ type: [AdminReportReasonCountResponse], description: 'Motifs des signalements ouverts, du plus fréquent au moins fréquent.' })
  reasons!: AdminReportReasonCountResponse[];

  @ApiProperty({ format: 'date-time' })
  latestAt!: string;
}

export class AdminReportTargetPageResponse implements AdminReportTargetPageDto {
  @ApiProperty({ type: [AdminReportTargetResponse], description: 'De la plus récemment signalée à la plus ancienne.' })
  items!: AdminReportTargetResponse[];

  @ApiProperty(NEXT_CURSOR)
  nextCursor!: string | null;
}

export class AdminReportResponse implements AdminReportDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiPropertyOptional({ type: UserSummaryResponse })
  reporter?: UserSummaryResponse;

  @ApiProperty(REPORT_REASON)
  reason!: ReportReason;

  @ApiProperty({ type: String, nullable: true })
  details!: string | null;

  @ApiProperty({ type: String, nullable: true })
  excerpt!: string | null;

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;

  @ApiPropertyOptional(REPORT_RESOLUTION)
  resolution?: ReportResolution;

  @ApiPropertyOptional({ format: 'date-time' })
  resolvedAt?: string;

  @ApiPropertyOptional({ type: UserSummaryResponse })
  resolvedBy?: UserSummaryResponse;
}

export class AdminReportTargetDetailResponse implements AdminReportTargetDetailDto {
  @ApiProperty({ type: AdminReportTargetResponse })
  target!: AdminReportTargetResponse;

  @ApiProperty({ type: [AdminReportResponse], description: 'Du plus récent au plus ancien, 100 au plus.' })
  reports!: AdminReportResponse[];
}

export function toAdminReportTargetDto(item: ModeratedReportTarget): AdminReportTargetDto {
  return {
    targetType: item.target.type,
    targetId: item.target.id,
    ...(item.targetUser ? { targetUser: toUserSummary(item.targetUser) } : {}),
    targetUsername: item.targetUsername,
    available: item.available,
    ...(item.thumbnailUrl ? { thumbnailUrl: item.thumbnailUrl } : {}),
    ...(item.videoId ? { videoId: item.videoId } : {}),
    ...(item.story ? { storyMediaUrl: item.story.mediaUrl, storyMediaType: item.story.mediaType } : {}),
    ...(item.excerpt ? { excerpt: item.excerpt } : {}),
    openCount: item.open?.openCount ?? 0,
    reasons: (item.open?.reasons ?? []).map(({ reason, count }) => ({ reason, count })),
    latestAt: item.latestAt.toISOString(),
  };
}

export function toAdminReportDto({ report, reporter, resolvedBy }: ModeratedReport): AdminReportDto {
  return {
    id: report.id,
    ...(reporter ? { reporter: toUserSummary(reporter) } : {}),
    reason: report.reason,
    details: report.details,
    excerpt: report.excerpt,
    createdAt: report.createdAt.toISOString(),
    ...(report.resolution ? { resolution: report.resolution } : {}),
    ...(report.resolvedAt ? { resolvedAt: report.resolvedAt.toISOString() } : {}),
    ...(resolvedBy ? { resolvedBy: toUserSummary(resolvedBy) } : {}),
  };
}

export function toAdminReportTargetDetailDto({ target, reports }: ReportTargetDetail): AdminReportTargetDetailDto {
  return { target: toAdminReportTargetDto(target), reports: reports.map(toAdminReportDto) };
}

// ─── Journal de modération (ADR-038) ─────────────────────────────────────────

export class AdminModerationActionResponse implements AdminModerationActionDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty({ enum: MODERATION_ACTION_TYPES, enumName: 'ModerationActionType' })
  action!: ModerationActionType;

  @ApiPropertyOptional({ type: UserSummaryResponse })
  admin?: UserSummaryResponse;

  @ApiProperty()
  adminUsername!: string;

  @ApiProperty(REPORT_TARGET_TYPE)
  targetType!: ReportTargetType;

  @ApiProperty({ format: 'uuid' })
  targetId!: string;

  @ApiPropertyOptional({ type: UserSummaryResponse })
  targetUser?: UserSummaryResponse;

  @ApiProperty({ type: String, nullable: true })
  targetUsername!: string | null;

  @ApiPropertyOptional(REPORT_REASON)
  reason?: ReportReason;

  @ApiProperty({ type: String, nullable: true, description: 'Suspension : motif saisi.' })
  note!: string | null;

  @ApiProperty({ type: String, nullable: true })
  excerpt!: string | null;

  @ApiProperty({ type: 'integer', minimum: 0, description: 'Signalements ouverts clos par cette action.' })
  reportsClosed!: number;

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;
}

export class AdminModerationActionPageResponse implements AdminModerationActionPageDto {
  @ApiProperty({ type: [AdminModerationActionResponse], description: 'Du plus récent au plus ancien.' })
  items!: AdminModerationActionResponse[];

  @ApiProperty(NEXT_CURSOR)
  nextCursor!: string | null;
}

// Comptes encore existants (administrateur, compte visé), lus par l'appelant.
export function toAdminModerationActionDto(action: ModerationAction, users: Map<string, User>): AdminModerationActionDto {
  const admin = action.adminId ? users.get(action.adminId) : undefined;
  const targetUser = action.targetUserId ? users.get(action.targetUserId) : undefined;
  return {
    id: action.id,
    action: action.action,
    ...(admin ? { admin: toUserSummary(admin) } : {}),
    adminUsername: action.adminUsername,
    targetType: action.target.type,
    targetId: action.target.id,
    ...(targetUser ? { targetUser: toUserSummary(targetUser) } : {}),
    targetUsername: action.targetUsername,
    ...(action.reason ? { reason: action.reason } : {}),
    note: action.note,
    excerpt: action.excerpt,
    reportsClosed: action.reportsClosed,
    createdAt: action.createdAt.toISOString(),
  };
}

export function toAdminGiftDto({ gift, sender, recipient, video }: GiftWithContext): AdminGiftDto {
  const dto: AdminGiftDto = {
    id: gift.id,
    gift: toGiftDto(gift.giftCode),
    amount: gift.amount,
    senderBalanceAfter: gift.senderBalanceAfter,
    videoId: gift.videoId,
    createdAt: gift.createdAt.toISOString(),
  };
  if (sender) dto.sender = toUserSummary(sender);
  if (recipient) dto.recipient = toUserSummary(recipient);
  if (video) dto.video = { id: video.id, thumbnailUrl: video.thumbnailUrl };
  return dto;
}
