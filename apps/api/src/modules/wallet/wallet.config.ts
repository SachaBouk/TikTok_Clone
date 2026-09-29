// Configuration RevenueCat (ADR-009), lue depuis l'environnement (voir .env.example).
export class RevenueCatConfig {
  constructor(
    // Valeur exacte de l'en-tête `Authorization` configuré pour le webhook dans le tableau de bord RevenueCat.
    // Absente : le webhook répond 503 (rien n'est crédité).
    readonly webhookAuthorization: string | null,
    // Code de la monnaie virtuelle des jetons dans RevenueCat ; les autres monnaies sont ignorées.
    readonly currencyCode: string,
    // Refuser les achats de test (SANDBOX).
    readonly rejectSandbox: boolean,
  ) {}

  static fromEnv(env: NodeJS.ProcessEnv = process.env): RevenueCatConfig {
    const authorization = env.REVENUECAT_WEBHOOK_AUTHORIZATION?.trim() || null;
    if (authorization && authorization.length < 16) {
      throw new Error('REVENUECAT_WEBHOOK_AUTHORIZATION : 16 caractères au moins. Voir .env.example.');
    }
    return new RevenueCatConfig(authorization, env.REVENUECAT_CURRENCY_CODE?.trim() || 'TKN', env.REVENUECAT_REJECT_SANDBOX === 'true');
  }
}
