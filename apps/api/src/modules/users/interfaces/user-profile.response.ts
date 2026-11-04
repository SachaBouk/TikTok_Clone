import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import type { ProfileNoteDto, UserProfileDto } from '@repo/shared';

// Note de profil (ADR-070), visible 24 h après sa publication.
export class ProfileNoteResponse implements ProfileNoteDto {
  @ApiProperty({ maxLength: 60, example: 'En vacances 🌴' })
  text!: string;

  @ApiProperty({ format: 'date-time' })
  postedAt!: string;

  @ApiProperty({ format: 'date-time' })
  expiresAt!: string;
}

// Schéma OpenAPI de UserProfileDto : `implements` garantit à la compilation que la classe suit le type partagé.
export class UserProfileResponse implements UserProfileDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty({ example: 'alice' })
  username!: string;

  @ApiProperty({ example: 'Alice' })
  displayName!: string;

  @ApiProperty({ type: String, nullable: true, format: 'uri' })
  avatarUrl!: string | null;

  @ApiProperty({ type: String, nullable: true })
  bio!: string | null;

  @ApiProperty({ type: 'integer', minimum: 0 })
  followersCount!: number;

  @ApiProperty({ type: 'integer', minimum: 0 })
  followingCount!: number;

  // Likes reçus sur ses vidéos publiées (ADR-056).
  @ApiProperty({ type: 'integer', minimum: 0 })
  likesCount!: number;

  // Pronoms (ADR-070).
  @ApiProperty({ type: String, nullable: true, maxLength: 20, example: 'elle' })
  pronouns!: string | null;

  // Absente sans note ou une fois expirée (ADR-070).
  @ApiPropertyOptional({ type: ProfileNoteResponse })
  note?: ProfileNoteResponse;

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;
}
