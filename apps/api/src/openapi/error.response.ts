import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

// Corps des réponses d'erreur de NestJS (HttpException), commun à toute l'API.
export class ErrorResponse {
  @ApiProperty({ example: 401 })
  statusCode!: number;

  // Une chaîne, ou la liste des erreurs de validation (400).
  @ApiProperty({
    oneOf: [{ type: 'string' }, { type: 'array', items: { type: 'string' } }],
    example: 'Email ou mot de passe incorrect',
  })
  message!: string | string[];

  @ApiPropertyOptional({ example: 'Unauthorized' })
  error?: string;
}
