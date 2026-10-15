import { ApiProperty } from '@nestjs/swagger';
import type { UserProfileDto } from '@repo/shared';

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

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;
}
