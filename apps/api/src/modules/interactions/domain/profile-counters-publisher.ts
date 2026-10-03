// Compteurs du profil d'un compte (abonnés, abonnements), poussés à ce compte sur ses appareils connectés quand un
// abonnement change (ADR-045, WebSocket, ADR-011). Au mieux : sans connexion, l'app relit son profil à la reconnexion.
export interface ProfileCounters {
  userId: string;
  followersCount: number;
  followingCount: number;
}

export abstract class ProfileCountersPublisher {
  abstract countersChanged(counters: ProfileCounters): Promise<void>;
}
