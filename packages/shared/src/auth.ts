// Réponse des routes /auth (ADR-010).
export interface AuthTokensDto {
  // JWT à envoyer dans l'en-tête `Authorization: Bearer …`.
  accessToken: string;
  // Durée de validité de l'access token, en secondes.
  accessTokenExpiresIn: number;
  // Opaque, à usage unique : chaque appel à /auth/refresh en renvoie un nouveau.
  refreshToken: string;
}
