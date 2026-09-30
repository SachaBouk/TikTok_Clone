import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import type {
  AdminCommentDto,
  AdminCommentPageDto,
  AdminCommentVideoDto,
  AdminCountDto,
  AdminStatsDto,
  AdminTokenStatsDto,
  AdminTokenTotalsDto,
  AdminUserDto,
  AdminUserPageDto,
  AdminVideoCountsDto,
  AdminVideoDto,
  AdminVideoPageDto,
  AdminWalletTransactionDto,
  AdminWalletTransactionPageDto,
  UserRole,
  VideoStatus,
  WalletTransactionKind,
} from '@repo/shared';
import { toUserSummary, UserSummaryResponse } from '../../users/interfaces/user-summary.response';
import type { AdminAccount, LedgerLine, ModeratedComment, ModeratedVideo, PlatformStats } from '../domain/admin';

// Schémas OpenAPI des DTO partagés : `implements` garantit à la compilation que chaque classe suit son type.

const VIDEO_STATUS = { enum: ['uploading', 'processing', 'ready', 'failed'], enumName: 'VideoStatus' };
const NEXT_CURSOR = { type: String, nullable: true, description: 'À renvoyer tel quel pour la page suivante ; null s’il n’y en a plus.' };

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

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;
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
}

export class AdminStatsResponse implements AdminStatsDto {
  @ApiProperty({ type: AdminCountResponse })
  users!: AdminCountResponse;

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

  @ApiProperty({ enum: ['purchase', 'refund', 'adjustment'], enumName: 'WalletTransactionKind' })
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

// Mappings explicites, champ par champ : rien n'est exposé par accident (clés de stockage, etc.).

export function toAdminUserDto({ user, isAdmin, videosCount, tokenBalance }: AdminAccount): AdminUserDto {
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
    createdAt: user.createdAt.toISOString(),
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
    users: { total: users.total, last7Days: users.last7Days },
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
    },
  };
}
