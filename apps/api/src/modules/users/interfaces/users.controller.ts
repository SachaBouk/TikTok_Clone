import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Put, Query, UseFilters } from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiConflictResponse,
  ApiCreatedResponse,
  ApiGoneResponse,
  ApiNoContentResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import type { AvatarUploadDto, UserInterestsDto, UsernameAvailabilityDto, UserProfileDto } from '@repo/shared';
import { ErrorResponse } from '../../../openapi/error.response';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { Public } from '../../auth/interfaces/public.decorator';
import { UsersService } from '../application/users.service';
import type { User } from '../domain/user';
import { AvatarUploadResponse } from './avatar-upload.response';
import { UserInterestsResponse, UsernameAvailabilityResponse } from './interests.responses';
import { UserErrorFilter } from './user-error.filter';
import { UserProfileResponse } from './user-profile.response';
import { CreateAvatarUploadRequest, SetAvatarRequest, SetInterestsRequest, UpdateProfileRequest, UsernameAvailabilityQuery } from './users.requests';

const UNAUTHORIZED = { type: ErrorResponse, description: 'Access token absent, invalide ou expiré.' };
const ACCOUNT_NOT_FOUND = { type: ErrorResponse, description: 'Compte supprimé.' };

// Couche `interfaces/` : traduit HTTP ↔ service applicatif, sans logique métier (ADR-003).
// Les routes `me` sont déclarées avant `:username`, sinon Express les capterait comme un pseudo.
@ApiTags('users')
@UseFilters(UserErrorFilter)
@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Get('me')
  @ApiOkResponse({ type: UserProfileResponse })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(ACCOUNT_NOT_FOUND)
  async getMyProfile(@CurrentUser() user: AuthenticatedUser): Promise<UserProfileDto> {
    return toProfileDto(await this.usersService.getById(user.userId));
  }

  // Seuls les champs présents changent.
  @Patch('me')
  @ApiOkResponse({ type: UserProfileResponse, description: 'Profil à jour.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Pseudo, nom ou bio invalide.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(ACCOUNT_NOT_FOUND)
  @ApiConflictResponse({ type: ErrorResponse, description: 'Pseudo déjà pris.' })
  async updateMyProfile(@CurrentUser() user: AuthenticatedUser, @Body() body: UpdateProfileRequest): Promise<UserProfileDto> {
    return toProfileDto(
      await this.usersService.updateProfile(user.userId, { username: body.username, displayName: body.displayName, bio: body.bio }),
    );
  }

  @Delete('me')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Compte et données associées supprimés.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Compte déjà supprimé.' })
  async deleteMyAccount(@CurrentUser() user: AuthenticatedUser): Promise<void> {
    await this.usersService.deleteAccount(user.userId);
  }

  // Photo de profil en deux temps : URL signée, PUT direct du fichier au stockage, puis confirmation.
  @Post('me/avatar/upload-url')
  @ApiCreatedResponse({ type: AvatarUploadResponse })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Format non pris en charge (JPEG ou PNG) ou fichier de plus de 5 Mio.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(ACCOUNT_NOT_FOUND)
  async createAvatarUpload(@CurrentUser() user: AuthenticatedUser, @Body() body: CreateAvatarUploadRequest): Promise<AvatarUploadDto> {
    const upload = await this.usersService.createAvatarUpload(user.userId, body.contentType, body.fileSize);
    return { avatarId: upload.avatarId, uploadUrl: upload.uploadUrl, expiresAt: upload.expiresAt.toISOString() };
  }

  // Remplace la photo de profil par celle envoyée ; l'ancienne est supprimée. Idempotent.
  @Put('me/avatar')
  @ApiOkResponse({ type: UserProfileResponse, description: 'Profil à jour.' })
  @ApiBadRequestResponse({
    type: ErrorResponse,
    description:
      'Fichier absent (envoi pas fait, expiré ou remplacé depuis), ou qui n’est pas une image JPEG ou PNG valide et carrée de 64 à 2048 px (ADR-046).',
  })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(ACCOUNT_NOT_FOUND)
  async setMyAvatar(@CurrentUser() user: AuthenticatedUser, @Body() body: SetAvatarRequest): Promise<UserProfileDto> {
    return toProfileDto(await this.usersService.setAvatar(user.userId, body.avatarId));
  }

  @Delete('me/avatar')
  @ApiOkResponse({ type: UserProfileResponse, description: 'Profil à jour, sans photo.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(ACCOUNT_NOT_FOUND)
  async removeMyAvatar(@CurrentUser() user: AuthenticatedUser): Promise<UserProfileDto> {
    return toProfileDto(await this.usersService.removeAvatar(user.userId));
  }

  // Centres d'intérêt du compte (ADR-055), privés.
  @Get('me/interests')
  @ApiOkResponse({ type: UserInterestsResponse })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(ACCOUNT_NOT_FOUND)
  async getMyInterests(@CurrentUser() user: AuthenticatedUser): Promise<UserInterestsDto> {
    return { interests: await this.usersService.getInterests(user.userId) };
  }

  @Put('me/interests')
  @ApiOkResponse({ type: UserInterestsResponse, description: 'Liste enregistrée, dans l’ordre du catalogue.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Code absent du catalogue, ou corps invalide.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse(ACCOUNT_NOT_FOUND)
  async setMyInterests(@CurrentUser() user: AuthenticatedUser, @Body() body: SetInterestsRequest): Promise<UserInterestsDto> {
    return { interests: await this.usersService.setInterests(user.userId, body.interests) };
  }

  // Inscription (ADR-055) : disponibilité d'un pseudo pendant la saisie. Publique ; déclarée avant `:username`.
  @Public()
  @Get('username-availability')
  @ApiOkResponse({ type: UsernameAvailabilityResponse })
  async checkUsernameAvailability(@Query() query: UsernameAvailabilityQuery): Promise<UsernameAvailabilityDto> {
    const availability = await this.usersService.checkUsernameAvailability(query.username);
    return availability.available ? { available: true } : { available: false, reason: availability.reason };
  }

  // Profil public : lisible en mode invité (ADR-010).
  @Public()
  @Get(':username')
  @ApiOkResponse({ type: UserProfileResponse })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Pseudo inconnu.' })
  @ApiGoneResponse({ type: ErrorResponse, description: 'Compte suspendu par un administrateur (ADR-037).' })
  async getProfile(@Param('username') username: string): Promise<UserProfileDto> {
    return toProfileDto(await this.usersService.getPublicProfile(username));
  }
}

// Mapping explicite : un champ ajouté au type de domaine n'est pas exposé par l'API sans le vouloir.
function toProfileDto(user: User): UserProfileDto {
  return {
    id: user.id,
    username: user.username,
    displayName: user.displayName,
    avatarUrl: user.avatarUrl,
    bio: user.bio,
    followersCount: user.followersCount,
    followingCount: user.followingCount,
    createdAt: user.createdAt.toISOString(),
  };
}
