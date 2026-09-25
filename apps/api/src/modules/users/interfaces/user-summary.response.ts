import { ApiProperty } from '@nestjs/swagger';
import type { UserSummaryDto } from '@repo/shared';
import type { User } from '../domain/user';

// Résumé d'un compte affiché à côté d'un contenu (auteur d'une vidéo du feed, d'un commentaire).
// `implements` garantit à la compilation que la classe suit le type partagé.
export class UserSummaryResponse implements UserSummaryDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty({ example: 'lea.martin' })
  username!: string;

  @ApiProperty({ example: 'Léa Martin' })
  displayName!: string;

  @ApiProperty({ type: String, nullable: true, format: 'uri' })
  avatarUrl!: string | null;
}

// Mapping explicite, partagé par les modules qui affichent un auteur.
export function toUserSummary(user: User): UserSummaryDto {
  return { id: user.id, username: user.username, displayName: user.displayName, avatarUrl: user.avatarUrl };
}
