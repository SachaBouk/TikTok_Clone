// Réponse d'erreur de l'API (corps `ErrorResponse` de NestJS : `message` est une chaîne ou une liste).
export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = 'ApiError';
  }

  static async from(response: Response): Promise<ApiError> {
    const body = (await response.json().catch(() => null)) as { message?: string | string[] } | null;
    const message = Array.isArray(body?.message) ? body.message.join(', ') : body?.message;
    return new ApiError(response.status, message || `Erreur ${response.status} de l’API`);
  }
}
