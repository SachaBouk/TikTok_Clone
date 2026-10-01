import 'server-only';
import type { AdminReportTargetDetailDto, AdminReportTargetPageDto, ReportTargetType } from '@repo/shared';
import { apiRequest, orNull } from '@/lib/api-client';

// File des signalements (ADR-038), groupés par cible.
export function listReportTargets(cursor?: string): Promise<AdminReportTargetPageDto> {
  return apiRequest('GET', '/admin/reports', { cursor, limit: 25 });
}

export function getReportTarget(type: ReportTargetType, id: string): Promise<AdminReportTargetDetailDto | null> {
  return orNull(apiRequest('GET', `/admin/reports/${type}/${encodeURIComponent(id)}`));
}

// Classement sans suite : les signalements ouverts de la cible sont clos, le contenu reste en ligne.
export function dismissReports(type: ReportTargetType, id: string): Promise<void> {
  return apiRequest('POST', `/admin/reports/${type}/${encodeURIComponent(id)}/dismiss`);
}
