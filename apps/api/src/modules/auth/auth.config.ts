// Configuration du module auth, lue depuis l'environnement (voir .env.example).
// L'API refuse de démarrer si elle est incomplète.
export class AuthConfig {
  constructor(
    readonly jwtAccessSecret: string,
    readonly accessTokenTtlSeconds: number,
    readonly refreshTokenTtlDays: number,
    readonly appleBundleId: string,
  ) {}

  static fromEnv(env: NodeJS.ProcessEnv = process.env): AuthConfig {
    const secret = env.JWT_ACCESS_SECRET ?? '';
    if (secret.length < 32) {
      throw new Error('JWT_ACCESS_SECRET manquant ou trop court (32 caractères minimum). Voir .env.example.');
    }
    const bundleId = env.APPLE_BUNDLE_ID;
    if (!bundleId) throw new Error('APPLE_BUNDLE_ID manquant. Voir .env.example.');

    return new AuthConfig(
      secret,
      positiveInt(env.JWT_ACCESS_TTL_SECONDS, 15 * 60, 'JWT_ACCESS_TTL_SECONDS'),
      positiveInt(env.REFRESH_TOKEN_TTL_DAYS, 30, 'REFRESH_TOKEN_TTL_DAYS'),
      bundleId,
    );
  }
}

function positiveInt(value: string | undefined, fallback: number, name: string): number {
  if (value === undefined || value === '') return fallback;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) throw new Error(`${name} doit être un entier positif.`);
  return parsed;
}
