import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, UseFilters } from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiConflictResponse,
  ApiCreatedResponse,
  ApiForbiddenResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiResponse,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import type { GiftCatalogDto, SentGiftDto } from '@repo/shared';
import { ErrorResponse } from '../../../openapi/error.response';
import { ApiTooManyRequests } from '../../../rate-limit/api-too-many-requests.decorator';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { Public } from '../../auth/interfaces/public.decorator';
import { WalletService } from '../application/wallet.service';
import { WalletErrorFilter } from './wallet-error.filter';
import { SendGiftRequest } from './wallet.requests';
import { GiftCatalogResponse, SentGiftResponse, toGiftCatalogItemDto, toSentGiftDto } from './wallet.responses';

// Cadeaux en jetons (ADR-050) : catalogue public, envoi sur une vidéo publiée. Le créateur reçoit des gains à part,
// non dépensables ; rien n'est public sur la vidéo.
@ApiTags('gifts')
@Controller()
@UseFilters(WalletErrorFilter)
export class GiftsController {
  constructor(private readonly walletService: WalletService) {}

  @Public()
  @Get('gifts/catalog')
  @ApiOkResponse({ type: GiftCatalogResponse })
  getGiftCatalog(): GiftCatalogDto {
    return { items: this.walletService.giftCatalog().map(toGiftCatalogItemDto) };
  }

  @Post('videos/:id/gifts')
  @HttpCode(201)
  @ApiCreatedResponse({
    type: SentGiftResponse,
    description: 'Cadeau envoyé, et solde après le débit. Renvoi avec le même `clientGiftId` : le même cadeau, sans nouveau débit.',
  })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Cadeau inconnu, sa propre vidéo, ou corps invalide.' })
  @ApiUnauthorizedResponse({ type: ErrorResponse, description: 'Access token absent, invalide ou expiré.' })
  @ApiResponse({ status: 402, type: ErrorResponse, description: 'Solde insuffisant.' })
  @ApiForbiddenResponse({ type: ErrorResponse, description: 'Blocage avec l’auteur, dans un sens ou dans l’autre.' })
  @ApiNotFoundResponse({ type: ErrorResponse, description: 'Vidéo non publiée, supprimée, ou d’un compte suspendu.' })
  @ApiConflictResponse({ type: ErrorResponse, description: 'Identifiant d’envoi déjà utilisé pour un autre cadeau ou une autre vidéo.' })
  @ApiTooManyRequests('Trop de cadeaux envoyés')
  async sendGift(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) videoId: string,
    @Body() body: SendGiftRequest,
  ): Promise<SentGiftDto> {
    return toSentGiftDto(await this.walletService.sendGift(user.userId, videoId, body.gift, body.clientGiftId.toLowerCase()));
  }
}
