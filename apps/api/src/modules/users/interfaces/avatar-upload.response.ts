import { ApiProperty } from '@nestjs/swagger';
import type { AvatarUploadDto } from '@repo/shared';

// Schéma OpenAPI de AvatarUploadDto : `implements` garantit à la compilation que la classe suit le type partagé.
export class AvatarUploadResponse implements AvatarUploadDto {
  @ApiProperty({ format: 'uuid', description: 'À renvoyer à `PUT /users/me/avatar` après l’envoi.' })
  avatarId!: string;

  @ApiProperty({
    format: 'uri',
    description: 'URL signée : un seul PUT du fichier, avec exactement les Content-Type et Content-Length annoncés.',
  })
  uploadUrl!: string;

  @ApiProperty({ format: 'date-time' })
  expiresAt!: string;
}
