import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import type {
  GiftCatalogDto,
  GiftCatalogItemDto,
  GiftDto,
  GiftVideoDto,
  ReceivedGiftDto,
  ReceivedGiftPageDto,
  SentGiftDto,
  WalletDto,
  WalletTransactionDto,
  WalletTransactionGiftDto,
  WalletTransactionKind,
  WalletTransactionPageDto,
} from '@repo/shared';
import { toUserSummary, UserSummaryResponse } from '../../users/interfaces/user-summary.response';
import type { GiftWithContext, SentGift, WalletHistoryItem } from '../application/wallet.service';
import type { WalletAmounts } from '../domain/gift';
import { giftDisplay, type GiftCatalogItem } from '../domain/gift-catalog';
import { WALLET_HISTORY_KINDS } from '../domain/wallet';

// Schémas OpenAPI des DTO partagés : `implements` garantit à la compilation que chaque classe suit son type.

export class WalletResponse implements WalletDto {
  @ApiProperty({ type: 'integer', minimum: 0, description: 'Jetons disponibles (achetés), seuls dépensables.' })
  balance!: number;

  @ApiProperty({ type: 'integer', minimum: 0, description: 'Jetons reçus en cadeaux : gains à part, ni dépensables ni retirables.' })
  earned!: number;
}

// Cadeaux (ADR-050).
export class GiftResponse implements GiftDto {
  @ApiProperty({ description: 'Code du catalogue.' })
  code!: string;

  @ApiProperty({ description: 'Nom (« Cadeau » pour un code retiré du catalogue).' })
  name!: string;

  @ApiProperty()
  emoji!: string;
}

export class GiftCatalogItemResponse extends GiftResponse implements GiftCatalogItemDto {
  @ApiProperty({ type: 'integer', minimum: 1, description: 'Prix en jetons.' })
  price!: number;
}

export class GiftCatalogResponse implements GiftCatalogDto {
  @ApiProperty({ type: [GiftCatalogItemResponse], description: 'Du moins cher au plus cher.' })
  items!: GiftCatalogItemResponse[];
}

export class WalletTransactionGiftResponse extends GiftResponse implements WalletTransactionGiftDto {
  // Absent : compte supprimé depuis.
  @ApiPropertyOptional({ type: UserSummaryResponse })
  recipient?: UserSummaryResponse;
}

export class SentGiftResponse implements SentGiftDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty({ type: GiftResponse })
  gift!: GiftResponse;

  @ApiProperty({ type: 'integer', minimum: 1, description: 'Prix payé, en jetons.' })
  amount!: number;

  @ApiProperty({ type: 'integer', minimum: 0, description: 'Solde après le débit.' })
  balance!: number;

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;
}

export class GiftVideoResponse implements GiftVideoDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty({ format: 'uri' })
  thumbnailUrl!: string;
}

export class ReceivedGiftResponse implements ReceivedGiftDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty({ type: GiftResponse })
  gift!: GiftResponse;

  @ApiProperty({ type: 'integer', minimum: 1 })
  amount!: number;

  // Absent : compte supprimé depuis.
  @ApiPropertyOptional({ type: UserSummaryResponse })
  sender?: UserSummaryResponse;

  // Absente : vidéo supprimée ou plus publiée.
  @ApiPropertyOptional({ type: GiftVideoResponse })
  video?: GiftVideoResponse;

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;
}

export class ReceivedGiftPageResponse implements ReceivedGiftPageDto {
  @ApiProperty({ type: [ReceivedGiftResponse], description: 'Du plus récent au plus ancien.' })
  items!: ReceivedGiftResponse[];

  @ApiProperty({ type: String, nullable: true, description: 'À renvoyer tel quel pour la page suivante ; null s’il n’y en a plus.' })
  nextCursor!: string | null;
}

export class WalletTransactionResponse implements WalletTransactionDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  // Achat d'un pack, remboursement par le store, ajustement manuel (tableau de bord RevenueCat), cadeau envoyé.
  @ApiProperty({ enum: WALLET_HISTORY_KINDS, enumName: 'WalletTransactionKind' })
  kind!: WalletTransactionKind;

  @ApiProperty({ type: 'integer', description: 'Variation du solde : positive pour un crédit, négative pour un retrait.' })
  amount!: number;

  @ApiProperty({ type: 'integer', minimum: 0, description: 'Solde juste après ce mouvement.' })
  balanceAfter!: number;

  @ApiProperty({ type: String, nullable: true, description: 'Produit acheté (pack de jetons).' })
  productId!: string | null;

  // Cadeau envoyé (sorte `giftSent`) seulement.
  @ApiPropertyOptional({ type: WalletTransactionGiftResponse })
  gift?: WalletTransactionGiftResponse;

  @ApiProperty({ format: 'date-time' })
  createdAt!: string;
}

export class WalletTransactionPageResponse implements WalletTransactionPageDto {
  @ApiProperty({ type: [WalletTransactionResponse], description: 'Du mouvement le plus récent au plus ancien.' })
  items!: WalletTransactionResponse[];

  @ApiProperty({ type: String, nullable: true, description: 'À renvoyer tel quel pour la page suivante ; null s’il n’y en a plus.' })
  nextCursor!: string | null;
}

export function toWalletDto(amounts: WalletAmounts): WalletDto {
  return { balance: amounts.balance, earned: amounts.earned };
}

// Mapping explicite : les identifiants RevenueCat et du store restent internes.
export function toWalletTransactionDto(item: WalletHistoryItem): WalletTransactionDto {
  if (item.kind === 'currency') {
    const { transaction } = item;
    return {
      id: transaction.id,
      kind: transaction.kind,
      amount: transaction.amount,
      balanceAfter: transaction.balanceAfter,
      productId: transaction.productId,
      createdAt: transaction.occurredAt.toISOString(),
    };
  }
  const { gift, recipient } = item;
  return {
    id: gift.id,
    kind: 'giftSent',
    amount: -gift.amount,
    balanceAfter: gift.senderBalanceAfter,
    productId: null,
    gift: { ...toGiftDto(gift.giftCode), ...(recipient ? { recipient: toUserSummary(recipient) } : {}) },
    createdAt: gift.createdAt.toISOString(),
  };
}

export function toGiftDto(code: string): GiftDto {
  const display = giftDisplay(code);
  return { code, name: display.name, emoji: display.emoji };
}

export function toGiftCatalogItemDto(item: GiftCatalogItem): GiftCatalogItemDto {
  return { code: item.code, name: item.name, emoji: item.emoji, price: item.price };
}

export function toSentGiftDto({ gift, balance }: SentGift): SentGiftDto {
  return { id: gift.id, gift: toGiftDto(gift.giftCode), amount: gift.amount, balance, createdAt: gift.createdAt.toISOString() };
}

export function toReceivedGiftDto({ gift, sender, video }: GiftWithContext): ReceivedGiftDto {
  const dto: ReceivedGiftDto = { id: gift.id, gift: toGiftDto(gift.giftCode), amount: gift.amount, createdAt: gift.createdAt.toISOString() };
  if (sender) dto.sender = toUserSummary(sender);
  if (video) dto.video = { id: video.id, thumbnailUrl: video.thumbnailUrl };
  return dto;
}
