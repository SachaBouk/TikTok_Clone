import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsEmail, IsNotEmpty, IsOptional, IsString, Length, Matches, MaxLength, MinLength } from 'class-validator';
import { MAX_DISPLAY_NAME_LENGTH, USERNAME_PATTERN } from '../../users/domain/profile-rules';
import { BIRTH_DATE_PATTERN, MAX_PASSWORD_LENGTH, MIN_PASSWORD_LENGTH, PASSWORD_PATTERN } from '../domain/registration-rules';

// Corps de requête validés par le ValidationPipe global (main.ts).
// Les décorateurs @ApiProperty décrivent les mêmes règles dans la spec OpenAPI (ADR-005) :
// les garder alignés avec les décorateurs class-validator.
// Règles du pseudo et du nom : celles du profil (module users), qui s'appliquent aussi à sa modification.

export class RegisterRequest {
  @ApiProperty({ format: 'email', maxLength: 254, example: 'alice@example.com' })
  @IsEmail()
  @MaxLength(254)
  email!: string;

  // Au moins une lettre et un chiffre (ADR-055).
  @ApiProperty({ minLength: MIN_PASSWORD_LENGTH, maxLength: MAX_PASSWORD_LENGTH, format: 'password', pattern: PASSWORD_PATTERN.source })
  @IsString()
  @MinLength(MIN_PASSWORD_LENGTH)
  @MaxLength(MAX_PASSWORD_LENGTH)
  @Matches(PASSWORD_PATTERN, { message: 'password : au moins une lettre et un chiffre' })
  password!: string;

  // Pseudo : minuscules, chiffres, points et underscores, comme sur TikTok.
  @ApiProperty({ pattern: USERNAME_PATTERN.source, example: 'alice' })
  @Matches(USERNAME_PATTERN, {
    message: 'username : 2 à 24 caractères parmi a-z, 0-9, « . » et « _ »',
  })
  username!: string;

  // Facultatif (ADR-055) : le pseudo par défaut.
  @ApiPropertyOptional({ minLength: 1, maxLength: MAX_DISPLAY_NAME_LENGTH, example: 'Alice' })
  @IsOptional()
  @IsString()
  @Length(1, MAX_DISPLAY_NAME_LENGTH)
  displayName?: string;

  // Date de naissance (ADR-055), jamais exposée : 13 ans au moins.
  @ApiProperty({ format: 'date', example: '2000-02-18' })
  @Matches(BIRTH_DATE_PATTERN, { message: 'birthDate : date au format AAAA-MM-JJ' })
  birthDate!: string;
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
