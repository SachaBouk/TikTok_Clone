import { Controller, Get, Query } from '@nestjs/common';
import { ApiBadRequestResponse, ApiOkResponse, ApiTags, ApiUnauthorizedResponse } from '@nestjs/swagger';
import type { WalletDto, WalletTransactionPageDto } from '@repo/shared';
import { ErrorResponse } from '../../../openapi/error.response';
import { CurrentUser, type AuthenticatedUser } from '../../auth/interfaces/current-user.decorator';
import { WalletService } from '../application/wallet.service';
import { WalletTransactionsQuery } from './wallet.requests';
import { toWalletTransactionDto, WalletResponse, WalletTransactionPageResponse } from './wallet.responses';

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
    return { balance: await this.walletService.getBalance(user.userId) };
  }

  @Get('transactions')
  @ApiOkResponse({ type: WalletTransactionPageResponse })
  @ApiBadRequestResponse({ type: ErrorResponse, description: 'Curseur ou limite invalide.' })
  @ApiUnauthorizedResponse(UNAUTHORIZED)
  async listWalletTransactions(@CurrentUser() user: AuthenticatedUser, @Query() query: WalletTransactionsQuery): Promise<WalletTransactionPageDto> {
    const page = await this.walletService.listTransactions(user.userId, query.cursor ?? null, query.limit);
    return { items: page.items.map(toWalletTransactionDto), nextCursor: page.nextCursor };
  }
}
