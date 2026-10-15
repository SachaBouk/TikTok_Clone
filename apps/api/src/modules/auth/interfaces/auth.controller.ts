import { Body, Controller, HttpCode, Ip, Post, UseFilters } from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiConflictResponse,
  ApiCreatedResponse,
  ApiNoContentResponse,
  ApiOkResponse,
  ApiTags,
  ApiForbiddenResponse,
  ApiTooManyRequestsResponse,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import type { AuthTokensDto } from '@repo/shared';
import { ApiTooManyRequests } from '../../../rate-limit/api-too-many-requests.decorator';
import { ErrorResponse } from '../../../openapi/error.response';
import { AuthService } from '../application/auth.service';
import type { AuthTokens } from '../domain/auth-account';
import { AuthErrorFilter } from './auth-error.filter';
import { AuthTokensResponse } from './auth-tokens.response';
import { AppleLoginRequest, LoginRequest, RefreshTokenRequest, RegisterRequest } from './auth.requests';
import { Public } from './public.decorator';

@ApiTags('auth')
@ApiBadRequestResponse({ type: ErrorResponse, description: 'Corps de requête invalide.' })
@Public()
@UseFilters(AuthErrorFilter)
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post('register')
  @ApiCreatedResponse({ type: AuthTokensResponse })
  @ApiConflictResponse({ type: ErrorResponse, description: 'Email ou pseudo déjà pris.' })
  @ApiTooManyRequests('Trop de comptes créés récemment depuis cette adresse IP')
  async register(@Body() body: RegisterRequest, @Ip() ip: string | undefined): Promise<AuthTokensDto> {
    return toTokensDto(await this.auth.register(body, ip || null));
  }

  @Post('login')
  @HttpCode(200)
  @ApiOkResponse({ type: AuthTokensResponse })
  @ApiUnauthorizedResponse({ type: ErrorResponse, description: 'Identifiant (email ou pseudo) ou mot de passe incorrect.' })
  @ApiForbiddenResponse({ type: ErrorResponse, description: 'Compte suspendu par un administrateur (ADR-037), après vérification de l’identité.' })
  @ApiTooManyRequestsResponse({
    type: ErrorResponse,
    description:
      'Trop d’échecs de connexion récents pour ce compte ou cette adresse IP : réessayer après le délai de l’en-tête Retry-After (secondes).',
    // Documenté pour que le client Swift généré l'expose (`headers.retryAfter`).
    headers: { 'Retry-After': { description: 'Secondes à attendre avant de réessayer.', schema: { type: 'integer', minimum: 1 } } },
  })
  async login(@Body() body: LoginRequest, @Ip() ip: string | undefined): Promise<AuthTokensDto> {
    return toTokensDto(await this.auth.login(body.identifier, body.password, ip || null));
  }

  @Post('apple')
  @HttpCode(200)
  @ApiOkResponse({ type: AuthTokensResponse, description: 'Compte créé à la première connexion.' })
  @ApiUnauthorizedResponse({ type: ErrorResponse, description: 'Identity token Apple invalide.' })
  @ApiConflictResponse({ type: ErrorResponse, description: 'Email Apple déjà utilisé par un compte email.' })
  @ApiForbiddenResponse({ type: ErrorResponse, description: 'Compte suspendu par un administrateur (ADR-037).' })
  async loginWithApple(@Body() body: AppleLoginRequest): Promise<AuthTokensDto> {
    return toTokensDto(await this.auth.loginWithApple(body));
  }

  @Post('refresh')
  @HttpCode(200)
  @ApiOkResponse({ type: AuthTokensResponse, description: 'Nouvelle paire ; l’ancien refresh token est invalidé.' })
  @ApiUnauthorizedResponse({ type: ErrorResponse, description: 'Session expirée, révoquée ou token réutilisé.' })
  async refresh(@Body() body: RefreshTokenRequest): Promise<AuthTokensDto> {
    return toTokensDto(await this.auth.refresh(body.refreshToken));
  }

  // Public : le refresh token suffit, l'access token peut déjà avoir expiré.
  @Post('logout')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Session révoquée (idempotent).' })
  async logout(@Body() body: RefreshTokenRequest): Promise<void> {
    await this.auth.logout(body.refreshToken);
  }
}

function toTokensDto(tokens: AuthTokens): AuthTokensDto {
  return {
    accessToken: tokens.accessToken,
    accessTokenExpiresIn: tokens.accessTokenExpiresIn,
    refreshToken: tokens.refreshToken,
  };
}
