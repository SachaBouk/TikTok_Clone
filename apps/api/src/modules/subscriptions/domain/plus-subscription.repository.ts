import type { PlusSubscription } from './plus-subscription';

// Table `plus_subscriptions` (ADR-073) : une ligne par compte, le dernier état connu.
export abstract class PlusSubscriptionRepository {
  abstract find(userId: string): Promise<PlusSubscription | null>;
  // Crée ou remplace la ligne du compte ; false si le compte n'existe plus.
  abstract save(subscription: PlusSubscription): Promise<boolean>;
  // Abonnements en cours (reconstruction du registre au démarrage).
  abstract listActive(now: Date): Promise<PlusSubscription[]>;
}
