import { Controller, Get, Query } from '@nestjs/common';
import { ApiBadRequestResponse, ApiOkResponse, ApiTags, ApiUnauthorizedResponse } from '@nestjs/swagger';
import type { ReceivedGiftPageDto, WalletDto, WalletTransactionPageDto } from '@repo/shared';
import { ErrorResponse } from '../../../openapi/error.response';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { WalletService } from '../application/wallet.service';
import { WalletTransactionsQuery } from './wallet.requests';
import {
  ReceivedGiftPageResponse,
  toReceivedGiftDto,
  toWalletDto,
  toWalletTransactionDto,
  WalletResponse,
  WalletTransactionPageResponse,
} from './wallet.responses';

const UNAUTHORIZED = { type: ErrorResponse, description: 'Access token absent, invalide ou expiré.' };

// Portefeuille du compte connecté (ADR-009). Le crédit arrive par le webhook RevenueCat, pas par l'app :
// après un achat, l'app attend l'événement WebSocket `walletUpdated` (ou relit cette route).
@ApiTags('wallet')
@Controller('wallet')
export class WalletController {
  constructor(private readonly walletService: WalletService) {}

  @Get()
  @ApiOkResponse({ type: WalletResponse })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async getWallet(@CurrentUser() user: AuthenticatedUser): Promise<WalletDto> {
    return toWalletDto(await this.walletService.getAmounts(user.userId));
  }

  // Achats, remboursements, ajustements et cadeaux envoyés (ADR-050), du plus récent au plus ancien.
  @Get('transactions')
  @ApiOkResponse({ type: WalletTransactionPageResponse })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Curseur ou limite invalide.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async listWalletTransactions(@CurrentUser() user: AuthenticatedUser, @Query() query: WalletTransactionsQuery): Promise<WalletTransactionPageDto> {
    const page = await this.walletService.listTransactions(user.userId, query.cursor ?? null, query.limit);
    return { items: page.items.map(toWalletTransactionDto), nextCursor: page.nextCursor };
  }

  // Cadeaux reçus (ADR-050) : ils alimentent les gains, pas le solde.
  @Get('gifts/received')
  @ApiOkResponse({ type: ReceivedGiftPageResponse })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Curseur ou limite invalide.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async listReceivedGifts(@CurrentUser() user: AuthenticatedUser, @Query() query: WalletTransactionsQuery): Promise<ReceivedGiftPageDto> {
    const page = await this.walletService.listReceivedGifts(user.userId, query.cursor ?? null, query.limit);
    return { items: page.items.map(toReceivedGiftDto), nextCursor: page.nextCursor };
  }
}
