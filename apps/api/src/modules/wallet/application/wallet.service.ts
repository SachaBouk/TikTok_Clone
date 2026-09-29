import type { UsersService } from '../../users/application/users.service';
import type { CurrencyEvent, WalletTransaction, WalletTransactionKind } from '../domain/wallet';
import type { WalletEventPublisher } from '../domain/wallet-events';
import type { WalletRepository } from '../domain/wallet.repository';

export interface WalletSettings {
  // Refuser les achats de test (SANDBOX) : à activer en production si TestFlight ne doit rien créditer.
  rejectSandbox: boolean;
}

// Suite donnée à un webhook : appliqué, déjà appliqué, ignoré (mouvement nul, sandbox refusée), ou enregistré
// sans compte (client RevenueCat inconnu de l'API).
export type WebhookOutcome = 'applied' | 'duplicate' | 'ignored' | 'unknownCustomer';

export interface WalletTransactionPage {
  items: WalletTransaction[];
  nextCursor: string | null;
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Service applicatif du module wallet (ADR-003, ADR-009). Le solde n'est modifié que par les webhooks
// RevenueCat (achats, remboursements, ajustements) ; la dépense (cadeaux) viendra avec les lives (ADR-016).
export class WalletService {
  constructor(
    private readonly wallets: WalletRepository,
    private readonly users: UsersService,
    private readonly events: WalletEventPublisher,
    private readonly settings: WalletSettings,
  ) {}

  getBalance(userId: string): Promise<number> {
    return this.wallets.getBalance(userId);
  }

  // Historique du compte, du plus récent au plus ancien. Curseur : identifiant du dernier mouvement reçu.
  async listTransactions(userId: string, cursor: string | null, limit: number): Promise<WalletTransactionPage> {
    const rows = await this.wallets.listTransactions(userId, cursor, limit + 1);
    const items = rows.slice(0, limit);
    return { items, nextCursor: rows.length > limit ? items.at(-1)!.id : null };
  }

  // Mouvement de jetons annoncé par RevenueCat. Idempotent : un webhook rejoué n'est appliqué qu'une fois.
  // Le solde à jour est poussé aux appareils du compte.
  async recordCurrencyEvent(event: CurrencyEvent): Promise<WebhookOutcome> {
    if (event.amount === 0) return 'ignored';
    if (this.settings.rejectSandbox && event.environment !== 'PRODUCTION') return 'ignored';

    const userId = await this.resolveCustomer(event.appUserIds);
    const result = await this.wallets.apply({
      eventId: event.eventId,
      userId,
      kind: kindOf(event),
      amount: event.amount,
      appUserId: event.appUserIds[0] ?? '',
      productId: event.productId,
      storeTransactionId: event.storeTransactionId,
      store: event.store,
      environment: event.environment,
      occurredAt: event.occurredAt,
    });
    if (result.status === 'duplicate') return 'duplicate';
    if (!userId || result.balance === null) return 'unknownCustomer';
    await this.events.balanceChanged(userId, result.balance);
    return 'applied';
  }

  // Premier identifiant RevenueCat qui est l'UUID d'un compte existant (l'app s'identifie avec l'UUID du compte ;
  // un achat fait avant l'identification garde l'identifiant anonyme en alias).
  private async resolveCustomer(appUserIds: string[]): Promise<string | null> {
    const candidates = [...new Set(appUserIds.filter((id) => UUID_PATTERN.test(id)).map((id) => id.toLowerCase()))];
    if (candidates.length === 0) return null;
    const existing = new Set((await this.users.getByIds(candidates)).map((user) => user.id));
    return candidates.find((id) => existing.has(id)) ?? null;
  }
}

function kindOf(event: CurrencyEvent): WalletTransactionKind {
  if (event.source === 'admin_api') return 'adjustment';
  return event.amount > 0 ? 'purchase' : 'refund';
}
