import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import type {
  FollowingLivesDto,
  LiveChatMessageDto,
  LiveConnectionDto,
  LiveDto,
  LiveEndReason,
  LiveHeartsDto,
  LiveItemDto,
  LiveRole,
  LiveStatsDto,
  LiveStatus,
  MessageLiveDto,
} from '@repo/shared';
import type { User } from '../../users/domain/user';
import { toUserSummary, UserSummaryResponse } from '../../users/interfaces/user-summary.response';
import type { LiveConnection, LiveItem } from '../application/live.service';
import { LIVE_END_REASONS, LIVE_STATUSES, type Live, type LiveMessage } from '../domain/live';

export class LiveStatsResponse implements LiveStatsDto {
  @ApiProperty({ type: 'integer', minimum: 0, description: 'Durée écoulée, ou totale une fois le live terminé.' })
  durationSeconds!: number;

  @ApiProperty({ type: 'integer', minimum: 0, description: 'Plus grand nombre de spectateurs en même temps.' })
  peakViewers!: number;

  @ApiProperty({ type: 'integer', minimum: 0, description: 'Spectateurs distincts, invités compris.' })
  viewersCount!: number;

  @ApiProperty({ type: 'integer', minimum: 0 })
  heartsCount!: number;

  @ApiProperty({ type: 'integer', minimum: 0 })
  giftsCount!: number;

  @ApiProperty({ type: 'integer', minimum: 0, description: 'Jetons reçus en cadeaux pendant le live.' })
  giftsAmount!: number;
}

export class LiveResponse implements LiveItemDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty({ format: 'uuid' })
  userId!: string;

  @ApiProperty({ type: String, nullable: true })
  title!: string | null;

  @ApiProperty({ enum: LIVE_STATUSES, enumName: 'LiveStatus' })
  status!: LiveStatus;

  @ApiProperty({ format: 'date-time' })
  startedAt!: string;

  @ApiProperty({ type: String, format: 'date-time', nullable: true })
  endedAt!: string | null;

  // Raison de la fin ; absente tant que le live est en cours (un enum nommé nullable produirait un `allOf`).
  @ApiPropertyOptional({ enum: LIVE_END_REASONS, enumName: 'LiveEndReason' })
  endReason?: LiveEndReason;

  @ApiProperty({ type: UserSummaryResponse })
  host!: UserSummaryResponse;

  // Pour l'auteur seulement.
  @ApiPropertyOptional({ type: LiveStatsResponse })
  stats?: LiveStatsResponse;
}

export class LiveChatMessageResponse implements LiveChatMessageDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty({ format: 'uuid' })
  liveId!: string;

  @ApiProperty({ type: UserSummaryResponse })
  user!: UserSummaryResponse;

  @ApiProperty()
  content!: string;

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;
}

export class LiveConnectionResponse implements LiveConnectionDto {
  @ApiProperty({ type: LiveResponse })
  live!: LiveResponse;

  // `host` : publier sa caméra et son micro ; `viewer` : regarder seulement.
  @ApiProperty({ enum: ['host', 'viewer'], enumName: 'LiveRole' })
  role!: LiveRole;

  @ApiProperty({ description: 'Serveur LiveKit (WebSocket).' })
  url!: string;

  @ApiProperty({ description: 'Jeton d’accès à la salle, signé par l’API.' })
  token!: string;

  @ApiProperty({ type: [LiveChatMessageResponse], description: 'Derniers messages du chat, du plus ancien au plus récent.' })
  recentMessages!: LiveChatMessageResponse[];
}

// Live partagé dans un message (ADR-053).
export class MessageLiveResponse implements MessageLiveDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty({ description: 'Faux une fois le live terminé, ou s’il est masqué au lecteur.' })
  available!: boolean;

  @ApiPropertyOptional({ type: String, nullable: true })
  title?: string | null;

  @ApiPropertyOptional({ type: UserSummaryResponse })
  host?: UserSummaryResponse;
}

export class LiveHeartsResponse implements LiveHeartsDto {
  @ApiProperty({ type: 'integer', minimum: 0, description: 'Cœurs reçus par le live depuis son début.' })
  total!: number;
}

export class FollowingLivesResponse implements FollowingLivesDto {
  @ApiProperty({ type: [LiveResponse], description: 'Lives en cours des comptes suivis, du plus récent au plus ancien.' })
  items!: LiveResponse[];
}

// Mapping explicite (ADR-003), partagé par le controller et les événements de la salle.
export function toLiveDto(live: Live): LiveDto {
  const dto: LiveDto = {
    id: live.id,
    userId: live.userId,
    title: live.title,
    status: live.status,
    startedAt: live.startedAt.toISOString(),
    endedAt: live.endedAt?.toISOString() ?? null,
  };
  if (live.endReason) dto.endReason = live.endReason;
  return dto;
}

export function toLiveItemDto({ live, host, stats }: LiveItem): LiveItemDto {
  const dto: LiveItemDto = { ...toLiveDto(live), host: toUserSummary(host) };
  if (stats) {
    dto.stats = {
      durationSeconds: stats.durationSeconds,
      peakViewers: stats.peakViewers,
      viewersCount: stats.viewersCount,
      heartsCount: stats.heartsCount,
      giftsCount: stats.giftsCount,
      giftsAmount: stats.giftsAmount,
    };
  }
  return dto;
}

export function toLiveChatMessageDto(message: LiveMessage, author: User): LiveChatMessageDto {
  return {
    id: message.id,
    liveId: message.liveId,
    user: toUserSummary(author),
    content: message.content,
    createdAt: message.createdAt.toISOString(),
  };
}

export function toLiveConnectionDto(connection: LiveConnection): LiveConnectionDto {
  return {
    live: toLiveItemDto(connection.item),
    role: connection.role,
    url: connection.url,
    token: connection.token,
    recentMessages: connection.recentMessages.map(({ message, author }) => toLiveChatMessageDto(message, author)),
  };
}

export function toMessageLiveDto(liveId: string, item: LiveItem | null): MessageLiveDto {
  if (!item) return { id: liveId, available: false };
  return { id: liveId, available: item.live.status === 'live', title: item.live.title, host: toUserSummary(item.host) };
}
