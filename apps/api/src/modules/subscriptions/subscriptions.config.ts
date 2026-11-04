// Configuration de l'API REST de RevenueCat (ADR-073), lue depuis l'environnement (voir .env.example).
export class SubscriptionsConfig {
  constructor(
    // Clé secrète (`sk_…`), côté serveur seulement ; null : les webhooks d'abonnement répondent 503.
    readonly secretApiKey: string | null,
    readonly apiUrl: string,
    // Refuser les achats de test (même réglage que les jetons, ADR-009).
    readonly rejectSandbox: boolean,
  ) {}

  static fromEnv(env: NodeJS.ProcessEnv = process.env): SubscriptionsConfig {
    return new SubscriptionsConfig(
      env.REVENUECAT_SECRET_API_KEY?.trim() || null,
      env.REVENUECAT_API_URL?.trim() || 'https://api.revenuecat.com',
      env.REVENUECAT_REJECT_SANDBOX === 'true',
    );
  }
}
