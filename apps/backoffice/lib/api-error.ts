// Réponse d'erreur de l'API (corps `ErrorResponse` de NestJS : `message` est une chaîne ou une liste).
export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
    // En-tête Retry-After d'une réponse 429 (secondes), s'il est présent.
    readonly retryAfterSeconds: number | null = null,
  ) {
    super(message);
    this.name = 'ApiError';
  }

  static async from(response: Response): Promise<ApiError> {
    const body = (await response.json().catch(() => null)) as { message?: string | string[] } | null;
    const message = Array.isArray(body?.message) ? body.message.join(', ') : body?.message;
    const retryAfter = Number.parseInt(response.headers.get('Retry-After') ?? '', 10);
    return new ApiError(response.status, message || `Erreur ${response.status} de l’API`, Number.isFinite(retryAfter) ? retryAfter : null);
  }
}
