// Configuration RevenueCat (ADR-009), lue depuis l'environnement (voir .env.example).
export class RevenueCatConfig {
  constructor(
    // Valeur exacte de l'en-tête `Authorization` configuré pour le webhook dans le tableau de bord RevenueCat.
    readonly webhookAuthorization: string | null,
    // Secret de signature HMAC du webhook (ADR-031) : chaque appel doit alors porter une signature valide
    // (`X-RevenueCat-Webhook-Signature`).
    readonly webhookSigningSecret: string | null,
    // Code de la monnaie virtuelle des jetons dans RevenueCat ; les autres monnaies sont ignorées.
    readonly currencyCode: string,
    // Refuser les achats de test (SANDBOX).
    readonly rejectSandbox: boolean,
  ) {}

  // Chaque protection configurée est exigée ; sans aucune, le webhook répond 503 (rien n'est crédité).
  get webhookConfigured(): boolean {
    return this.webhookAuthorization !== null || this.webhookSigningSecret !== null;
  }

  static fromEnv(env: NodeJS.ProcessEnv = process.env): RevenueCatConfig {
    const authorization = env.REVENUECAT_WEBHOOK_AUTHORIZATION?.trim() || null;
    if (authorization && authorization.length < 16) {
      throw new Error('REVENUECAT_WEBHOOK_AUTHORIZATION : 16 caractères au moins. Voir .env.example.');
    }
    const signingSecret = env.REVENUECAT_WEBHOOK_SIGNING_SECRET?.trim() || null;
    if (signingSecret && signingSecret.length < 16) {
      throw new Error('REVENUECAT_WEBHOOK_SIGNING_SECRET : 16 caractères au moins. Voir .env.example.');
    }
    return new RevenueCatConfig(
      authorization,
      signingSecret,
      env.REVENUECAT_CURRENCY_CODE?.trim() || 'TKN',
      env.REVENUECAT_REJECT_SANDBOX === 'true',
    );
  }
}
