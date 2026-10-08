import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsString, IsUUID, Max, MaxLength, Min, MinLength } from 'class-validator';
import { DEFAULT_PAGE_SIZE, MAX_MESSAGE_LENGTH, MAX_PAGE_SIZE } from '../domain/messaging';

// Corps et paramètres de requête validés par le ValidationPipe global (main.ts).

export class OpenConversationRequest {
  @ApiProperty({ example: 'lea.martin', description: 'Pseudo de l’autre participant.' })
  @IsString()
  @MinLength(1)
  username!: string;
}

// Texte, vidéo partagée, ou les deux (au moins l'un des deux).
export class SendMessageRequest {
  @ApiPropertyOptional({ maxLength: MAX_MESSAGE_LENGTH, example: 'Salut !' })
  @IsOptional()
  @IsString()
  @MaxLength(MAX_MESSAGE_LENGTH)
  content?: string;

  @ApiPropertyOptional({ format: 'uuid', description: 'Vidéo publiée à partager (comptée comme un partage).' })
  @IsOptional()
  @IsUUID()
  videoId?: string;

  @ApiPropertyOptional({
    format: 'uuid',
    description: 'Story active de l’autre participant à laquelle répond le message (ADR-051) ; `content` est alors obligatoire.',
  })
  @IsOptional()
  @IsUUID()
  storyId?: string;

  @ApiPropertyOptional({
    format: 'uuid',
    description:
      'Identifiant d’envoi choisi par l’app (ADR-044). Le renvoyer pour le même message rend celui déjà créé (même réponse), sans en créer un second ni le compter dans les limites.',
  })
  @IsOptional()
  @IsUUID()
  clientMessageId?: string;
}

export class MarkConversationReadRequest {
  @ApiPropertyOptional({
    format: 'uuid',
    description: 'Message le plus récent affiché : lu jusqu’à celui-ci. Absent : jusqu’au dernier message.',
  })
  @IsOptional()
  @IsUUID()
  upToId?: string;
}

export class PageQuery {
  @ApiPropertyOptional({ format: 'uuid', description: '`nextCursor` de la page précédente.' })
  @IsOptional()
  @IsUUID()
  cursor?: string;

  @ApiPropertyOptional({ type: 'integer', minimum: 1, maximum: MAX_PAGE_SIZE, default: DEFAULT_PAGE_SIZE })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(MAX_PAGE_SIZE)
  limit: number = DEFAULT_PAGE_SIZE;
}
