import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsEmail, IsNotEmpty, IsOptional, IsString, Length, Matches, MaxLength, MinLength } from 'class-validator';
import { MAX_DISPLAY_NAME_LENGTH, USERNAME_PATTERN } from '../../users/domain/profile-rules';

// Corps de requête validés par le ValidationPipe global (main.ts).
// Les décorateurs @ApiProperty décrivent les mêmes règles dans la spec OpenAPI (ADR-005) :
// les garder alignés avec les décorateurs class-validator.
// Règles du pseudo et du nom : celles du profil (module users), qui s'appliquent aussi à sa modification.

export class RegisterRequest {
  @ApiProperty({ format: 'email', maxLength: 254, example: 'alice@example.com' })
  @IsEmail()
  @MaxLength(254)
  email!: string;

  @ApiProperty({ minLength: 8, maxLength: 128, format: 'password' })
  @IsString()
  @MinLength(8)
  @MaxLength(128)
  password!: string;

  // Pseudo : minuscules, chiffres, points et underscores, comme sur TikTok.
  @ApiProperty({ pattern: USERNAME_PATTERN.source, example: 'alice' })
  @Matches(USERNAME_PATTERN, {
    message: 'username : 2 à 24 caractères parmi a-z, 0-9, « . » et « _ »',
  })
  username!: string;

  @ApiProperty({ minLength: 1, maxLength: MAX_DISPLAY_NAME_LENGTH, example: 'Alice' })
  @IsString()
  @Length(1, MAX_DISPLAY_NAME_LENGTH)
  displayName!: string;
}

// Pas de règle de format ici : la connexion ne doit rien révéler des règles d'inscription.
export class LoginRequest {
  // Email ou pseudo (ADR-055) ; un « @ » devant le pseudo est ignoré.
  @ApiProperty({ maxLength: 254, example: 'alice@example.com' })
  @IsString()
  @IsNotEmpty()
  @MaxLength(254)
  identifier!: string;

  @ApiProperty({ maxLength: 128, format: 'password' })
  @IsString()
  @IsNotEmpty()
  @MaxLength(128)
  password!: string;
}

export class AppleLoginRequest {
  @ApiProperty({ description: 'Identity token (JWT) renvoyé par Sign in with Apple.' })
  @IsString()
  @IsNotEmpty()
  identityToken!: string;

  @ApiPropertyOptional({
    maxLength: MAX_DISPLAY_NAME_LENGTH,
    description: 'Nom fourni par Apple, uniquement à la première connexion.',
  })
  @IsOptional()
  @IsString()
  @MaxLength(MAX_DISPLAY_NAME_LENGTH)
  displayName?: string;
}

export class RefreshTokenRequest {
  @ApiProperty()
  @IsString()
  @IsNotEmpty()
  refreshToken!: string;
}
