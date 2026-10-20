import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import type { SoundDto, SoundListDto, SoundPageDto, SoundViewerStateDto } from '@repo/shared';
import { toUserSummary, UserSummaryResponse } from '../../users/interfaces/user-summary.response';
import type { SoundItem } from '../application/feed.service';

export class SoundViewerStateResponse implements SoundViewerStateDto {
  @ApiProperty()
  favorited!: boolean;
}

// Son repris d'une vidéo publiée (ADR-064) : « Son original - @pseudo ».
export class SoundResponse implements SoundDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty({ format: 'uuid', description: "Vidéo d'où vient le son." })
  videoId!: string;

  @ApiProperty({ type: UserSummaryResponse })
  author!: UserSummaryResponse;

  @ApiProperty({ format: 'uri', description: 'Fichier AAC du son.' })
  audioUrl!: string;

  @ApiProperty({ description: 'Durée, en secondes.' })
  duration!: number;

  @ApiProperty({ format: 'uri', description: "Miniature de la vidéo d'origine." })
  coverUrl!: string;

  @ApiProperty({ type: 'integer', description: 'Vidéos publiques publiées qui utilisent ce son.' })
  usesCount!: number;

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;

  @ApiPropertyOptional({ type: SoundViewerStateResponse })
  viewer?: SoundViewerStateResponse;
}

export class SoundPageResponse implements SoundPageDto {
  @ApiProperty({ type: [SoundResponse] })
  items!: SoundResponse[];

  @ApiProperty({ type: String, nullable: true, description: 'À renvoyer tel quel pour la page suivante ; nul à la fin.' })
  nextCursor!: string | null;
}

export class SoundListResponse implements SoundListDto {
  @ApiProperty({ type: [SoundResponse] })
  items!: SoundResponse[];
}

// Mapping explicite, champ par champ (ADR-003).
export function toSoundDto({ sound, author, favorited }: SoundItem): SoundDto {
  return {
    id: sound.id,
    videoId: sound.videoId,
    author: toUserSummary(author),
    audioUrl: sound.audioUrl,
    duration: sound.durationMs / 1000,
    coverUrl: sound.coverUrl,
    usesCount: sound.usesCount,
    createdAt: sound.createdAt.toISOString(),
    viewer: { favorited },
  };
}
