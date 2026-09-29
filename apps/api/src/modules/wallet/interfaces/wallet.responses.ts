import { ApiProperty } from '@nestjs/swagger';
import type { WalletDto, WalletTransactionDto, WalletTransactionKind, WalletTransactionPageDto } from '@repo/shared';
import type { WalletTransaction } from '../domain/wallet';

// Schémas OpenAPI des DTO partagés : `implements` garantit à la compilation que chaque classe suit son type.

export class WalletResponse implements WalletDto {
  @ApiProperty({ type: 'integer', minimum: 0, description: 'Jetons disponibles.' })
  balance!: number;
}

export class WalletTransactionResponse implements WalletTransactionDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  // Achat d'un pack, remboursement par le store, ajustement manuel (tableau de bord RevenueCat).
  @ApiProperty({ enum: ['purchase', 'refund', 'adjustment'], enumName: 'WalletTransactionKind' })
  kind!: WalletTransactionKind;

  @ApiProperty({ type: 'integer', description: 'Variation du solde : positive pour un crédit, négative pour un retrait.' })
  amount!: number;

  @ApiProperty({ type: 'integer', minimum: 0, description: 'Solde juste après ce mouvement.' })
  balanceAfter!: number;

  @ApiProperty({ type: String, nullable: true, description: 'Produit acheté (pack de jetons).' })
  productId!: string | null;

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;
}

export class WalletTransactionPageResponse implements WalletTransactionPageDto {
  @ApiProperty({ type: [WalletTransactionResponse], description: 'Du mouvement le plus récent au plus ancien.' })
  items!: WalletTransactionResponse[];

  @ApiProperty({ type: String, nullable: true, description: 'À renvoyer tel quel pour la page suivante ; null s’il n’y en a plus.' })
  nextCursor!: string | null;
}

// Mapping explicite : les identifiants RevenueCat et du store restent internes.
export function toWalletTransactionDto(transaction: WalletTransaction): WalletTransactionDto {
  return {
    id: transaction.id,
    kind: transaction.kind,
    amount: transaction.amount,
    balanceAfter: transaction.balanceAfter,
    productId: transaction.productId,
    createdAt: transaction.occurredAt.toISOString(),
  };
}
