import { ApiProperty } from '@nestjs/swagger';
import type { AuthTokensDto } from '@repo/shared';

// Schéma OpenAPI de AuthTokensDto : `implements` garantit à la compilation que la classe suit le type partagé.
export class AuthTokensResponse implements AuthTokensDto {
  @ApiProperty({ description: 'JWT à envoyer dans l’en-tête `Authorization: Bearer …`.' })
  accessToken!: string;

  @ApiProperty({ type: 'integer', description: 'Durée de validité de l’access token, en secondes.', example: 900 })
  accessTokenExpiresIn!: number;

  @ApiProperty({ description: 'Opaque, à usage unique : chaque appel à /auth/refresh en renvoie un nouveau.' })
  refreshToken!: string;
}
