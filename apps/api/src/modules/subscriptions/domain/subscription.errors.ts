// Erreurs métier du module subscriptions (ADR-073).
export class SubscriptionError extends Error {}

// Webhook d'abonnement reçu sans clé secrète RevenueCat configurée : 503 (RevenueCat le renverra).
export class SubscriptionsNotConfiguredError extends SubscriptionError {
  constructor() {
    super('Abonnements non configurés : REVENUECAT_SECRET_API_KEY manquante');
    this.name = 'SubscriptionsNotConfiguredError';
  }
}
