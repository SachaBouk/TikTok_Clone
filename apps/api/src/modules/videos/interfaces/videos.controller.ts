import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post, UseFilters } from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiConflictResponse,
  ApiCreatedResponse,
  ApiNoContentResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import type { VideoDto, VideoUploadDto } from '@repo/shared';
import { ApiTooManyRequests } from '../../../rate-limit/api-too-many-requests.decorator';
import { ErrorResponse } from '../../../openapi/error.response';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { Public } from '../../auth/interfaces/public.decorator';
import { VideosService, type VideoUpload } from '../application/videos.service';
import { VideoErrorFilter } from './video-error.filter';
import { CompleteUploadRequest, CreateUploadRequest, SetVideoVisibilityRequest } from './videos.requests';
import { toVideoDto, VideoResponse, VideoUploadResponse } from './videos.responses';

const UNAUTHORIZED = { type: ErrorResponse, description: 'Access token absent, invalide ou expiré.' };

@ApiTags('videos')
@UseFilters(VideoErrorFilter)
@Controller('videos')
export class VideosController {
  constructor(private readonly videos: VideosService) {}

  // Publier nécessite un compte (ADR-010).
  @Post('upload-url')
  @ApiCreatedResponse({
    type: VideoUploadResponse,
    description:
      'Vidéo créée en `uploading`. Envoyer chaque partie (`partSize` octets, la dernière plus petite) en PUT sur son URL, ' +
      'garder les en-têtes `ETag`, puis appeler `completeUpload`. Une partie en échec se renvoie sur la même URL tant qu’elle est valide.',
  })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Format non pris en charge ou fichier trop volumineux.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiTooManyRequests('Trop d’envois de vidéos démarrés récemment (ADR-039)')
  async createUpload(@CurrentUser() user: AuthenticatedUser, @Body() body: CreateUploadRequest): Promise<VideoUploadDto> {
    return toUploadDto(
      await this.videos.createUpload(user.userId, {
        contentType: body.contentType,
        fileSize: body.fileSize,
        description: body.description,
        visibility: body.visibility,
      }),
    );
  }

  @Patch(':id/uploaded')
  @HttpCode(200)
  @ApiOkResponse({ type: VideoResponse, description: 'Upload assemblé : la vidéo passe en `processing` et le transcodage est lancé.' })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Parties manquantes ou ETags incorrects : renvoyer les parties, puis réessayer.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Vidéo inconnue ou appartenant à un autre utilisateur.' })
  @ApiConflictResponse({ type: ErrorResponse, description: 'Upload déjà confirmé.' })
  async completeUpload(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) id: string,
    @Body() body: CompleteUploadRequest,
  ): Promise<VideoDto> {
    return toVideoDto(await this.videos.completeUpload(user.userId, id, body.parts));
  }

  // Vidéo privée ou publique (ADR-061), par son auteur, quel que soit son statut.
  @Patch(':id/visibility')
  @HttpCode(200)
  @ApiOkResponse({ type: VideoResponse })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Vidéo inconnue ou appartenant à un autre utilisateur.' })
  async setVideoVisibility(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) id: string,
    @Body() body: SetVideoVisibilityRequest,
  ): Promise<VideoDto> {
    return toVideoDto(await this.videos.setVisibility(user.userId, id, body.visibility));
  }

  // Par son auteur, quel que soit le statut. Likes, commentaires, favoris, republications et notifications
  // disparaissent avec elle ; ses fichiers sont supprimés du stockage peu après.
  @Delete(':id')
  @HttpCode(204)
  @ApiNoContentResponse({ description: 'Vidéo supprimée.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Vidéo inconnue, déjà supprimée, ou appartenant à un autre utilisateur.' })
  async deleteVideo(@CurrentUser() user: AuthenticatedUser, @Param('id', new ParseUUIDPipe()) id: string): Promise<void> {
    await this.videos.deleteVideo(user.userId, id);
  }

  // Public (mode invité) pour une vidéo `ready` ; l'auteur, connecté, voit aussi ses vidéos en cours de traitement.
  @Public()
  @Get(':id')
  @ApiOkResponse({ type: VideoResponse })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Vidéo inconnue, ou pas encore prête et appartenant à un autre utilisateur.' })
  async getVideo(@CurrentUser() user: AuthenticatedUser | undefined, @Param('id', new ParseUUIDPipe()) id: string): Promise<VideoDto> {
    return toVideoDto(await this.videos.getVideo(id, user?.userId ?? null));
  }
}

function toUploadDto(upload: VideoUpload): VideoUploadDto {
  return {
    video: toVideoDto(upload.video),
    partSize: upload.partSize,
    parts: upload.parts.map((part) => ({ partNumber: part.partNumber, url: part.url })),
    expiresAt: upload.expiresAt.toISOString(),
  };
}
