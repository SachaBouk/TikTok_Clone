import type { PlusStatus } from './plus-subscription';

// État de l'abonnement poussé à tous les appareils du compte (ADR-073, événement `plusChanged`).
export abstract class PlusEventPublisher {
  abstract plusChanged(userId: string, status: PlusStatus): Promise<void>;
}
