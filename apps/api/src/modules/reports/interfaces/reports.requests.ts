import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import type { CreateReportDto, ReportReason, ReportTargetType } from '@repo/shared';
import { IsIn, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';
import { MAX_REPORT_DETAILS_LENGTH, REPORT_REASONS, REPORT_TARGET_TYPES } from '../domain/report';

// Corps validé par le ValidationPipe global (main.ts). Enums nommés sans description : sinon `allOf` (voir CLAUDE.md).
export class CreateReportRequest implements CreateReportDto {
  @ApiProperty({ enum: REPORT_TARGET_TYPES, enumName: 'ReportTargetType' })
  @IsIn(REPORT_TARGET_TYPES)
  targetType!: ReportTargetType;

  @ApiProperty({ format: 'uuid', description: 'Identifiant de la vidéo, du commentaire ou du compte.' })
  @IsUUID()
  targetId!: string;

  @ApiProperty({ enum: REPORT_REASONS, enumName: 'ReportReason' })
  @IsIn(REPORT_REASONS)
  reason!: ReportReason;

  @ApiPropertyOptional({ maxLength: MAX_REPORT_DETAILS_LENGTH, description: 'Précision facultative.' })
  @IsOptional()
  @IsString()
  @MaxLength(MAX_REPORT_DETAILS_LENGTH)
  details?: string;
}
