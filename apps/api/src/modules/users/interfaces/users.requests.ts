import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsInt, IsOptional, IsString, IsUUID, Matches, Max, MaxLength, Min, MinLength, ValidateIf } from 'class-validator';
import { AVATAR_CONTENT_TYPES, MAX_AVATAR_SIZE_BYTES, MAX_BIO_LENGTH, MAX_DISPLAY_NAME_LENGTH, USERNAME_PATTERN } from '../domain/profile-rules';

// Corps de requête validés par le ValidationPipe global (main.ts) ; limites issues des règles du domaine.

// Seuls les champs présents changent. `username` et `displayName` ne peuvent pas être null ;
// `bio` à null (ou vide) efface la bio.
export class UpdateProfileRequest {
  @ApiPropertyOptional({ pattern: USERNAME_PATTERN.source, example: 'alice' })
  @ValidateIf((request: UpdateProfileRequest) => request.username !== undefined)
  @Matches(USERNAME_PATTERN, { message: 'username : 2 à 24 caractères parmi a-z, 0-9, « . » et « _ »' })
  username?: string;

  @ApiPropertyOptional({ minLength: 1, maxLength: MAX_DISPLAY_NAME_LENGTH, example: 'Alice' })
  @ValidateIf((request: UpdateProfileRequest) => request.displayName !== undefined)
  @IsString()
  @MinLength(1)
  @MaxLength(MAX_DISPLAY_NAME_LENGTH)
  displayName?: string;

  @ApiPropertyOptional({ type: String, nullable: true, maxLength: MAX_BIO_LENGTH, example: 'Danse et cuisine 🍜' })
  @IsOptional()
  @IsString()
  @MaxLength(MAX_BIO_LENGTH)
  bio?: string | null;
}

export class CreateAvatarUploadRequest {
  @ApiProperty({ enum: AVATAR_CONTENT_TYPES, example: 'image/jpeg' })
  @IsIn(AVATAR_CONTENT_TYPES)
  contentType!: string;

  @ApiProperty({ type: 'integer', minimum: 1, maximum: MAX_AVATAR_SIZE_BYTES, description: 'Taille du fichier en octets.' })
  @IsInt()
  @Min(1)
  @Max(MAX_AVATAR_SIZE_BYTES)
  fileSize!: number;
}

export class SetAvatarRequest {
  @ApiProperty({ format: 'uuid', description: '`avatarId` renvoyé par `POST /users/me/avatar/upload-url`.' })
  @IsUUID()
  avatarId!: string;
}
