import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { ArrayMaxSize, ArrayMinSize, IsArray, IsInt, IsOptional, IsString, IsUUID, Max, MaxLength, Min, MinLength } from 'class-validator';
import {
  DEFAULT_PAGE_SIZE,
  MAX_GROUP_MEMBERS,
  MAX_GROUP_NAME_LENGTH,
  DEFAULT_SEARCH_RESULTS,
  MAX_MESSAGE_LENGTH,
  MAX_PAGE_SIZE,
  MAX_SEARCH_QUERY_LENGTH,
  MAX_SEARCH_RESULTS,
} from '../domain/messaging';

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

  @ApiPropertyOptional({ format: 'uuid', description: 'Live en cours partagé (ADR-053) ; `content` facultatif.' })
  @IsOptional()
  @IsUUID()
  liveId?: string;

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

// Recherche dans ses messages (ADR-058).
export class MessageSearchQuery {
  @ApiProperty({ minLength: 1, maxLength: MAX_SEARCH_QUERY_LENGTH, description: 'Texte cherché, sans casse.' })
  @IsString()
  @MinLength(1)
  @MaxLength(MAX_SEARCH_QUERY_LENGTH)
  q!: string;

  @ApiPropertyOptional({ type: 'integer', minimum: 1, maximum: MAX_SEARCH_RESULTS, default: DEFAULT_SEARCH_RESULTS })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(MAX_SEARCH_RESULTS)
  limit: number = DEFAULT_SEARCH_RESULTS;
}

// Chats de groupe (ADR-059). Les règles (amis, nombre de membres) sont vérifiées par le service.
export class CreateGroupRequest {
  @ApiProperty({
    type: [String],
    format: 'uuid',
    minItems: 1,
    maxItems: MAX_GROUP_MEMBERS - 1,
    description: 'Amis à ajouter (abonnés mutuels), au moins 2, créateur non compris.',
  })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(MAX_GROUP_MEMBERS - 1)
  @IsUUID('all', { each: true })
  userIds!: string[];

  @ApiPropertyOptional({ maxLength: MAX_GROUP_NAME_LENGTH, description: 'Nom du groupe ; absent ou vide : les noms des membres.' })
  @IsOptional()
  @IsString()
  @MaxLength(MAX_GROUP_NAME_LENGTH)
  name?: string;
}

export class AddGroupMembersRequest {
  @ApiProperty({ type: [String], format: 'uuid', minItems: 1, maxItems: MAX_GROUP_MEMBERS - 1, description: 'Amis à ajouter.' })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(MAX_GROUP_MEMBERS - 1)
  @IsUUID('all', { each: true })
  userIds!: string[];
}

export class RenameGroupRequest {
  @ApiProperty({ maxLength: MAX_GROUP_NAME_LENGTH, description: 'Nouveau nom ; vide : nom retiré.' })
  @IsString()
  @MaxLength(MAX_GROUP_NAME_LENGTH)
  name!: string;
}
