import { randomUUID } from 'node:crypto';
import type { NewReport, OpenReportTarget, Report, ReportResolution, ReportTarget } from '../domain/report';
import { ReportRepository } from '../domain/report.repository';

// Adaptateur en mémoire pour les tests : identifiants croissants (comme les UUID v7) et horloge injectable.
export class InMemoryReportRepository extends ReportRepository {
  readonly reports: Report[] = [];
  private sequence = 0;

  constructor(private readonly now: () => Date = () => new Date()) {
    super();
  }

  async create(report: NewReport): Promise<boolean> {
    if (this.reports.some((r) => r.reporterId === report.reporterId && sameTarget(r.target, report.target) && !r.resolution)) return false;
    this.reports.push({
      id: `${String(++this.sequence).padStart(8, '0')}-${randomUUID().slice(9)}`,
      reporterId: report.reporterId,
      target: report.target,
      targetUserId: report.targetUserId,
      reason: report.reason,
      details: report.details,
      excerpt: report.excerpt,
      createdAt: this.now(),
      resolution: null,
      resolvedAt: null,
      resolvedBy: null,
    });
    return true;
  }

  async listOpenTargets(beforeId: string | null, limit: number): Promise<OpenReportTarget[]> {
    return this.groups()
      .filter((g) => !beforeId || g.latestId < beforeId)
      .slice(0, limit);
  }

  async findOpenTarget(target: ReportTarget): Promise<OpenReportTarget | null> {
    return this.groups().find((g) => sameTarget(g.target, target)) ?? null;
  }

  async listForTarget(target: ReportTarget, limit: number): Promise<Report[]> {
    return this.newestFirst()
      .filter((r) => sameTarget(r.target, target))
      .slice(0, limit);
  }

  async resolveTarget(target: ReportTarget, resolution: ReportResolution, resolvedBy: string, at: Date): Promise<number> {
    return this.resolve((r) => sameTarget(r.target, target), resolution, resolvedBy, at);
  }

  async resolveForUser(targetUserId: string, resolution: ReportResolution, resolvedBy: string, at: Date): Promise<number> {
    return this.resolve((r) => r.targetUserId === targetUserId, resolution, resolvedBy, at);
  }

  async countOpenTargets(): Promise<number> {
    return this.groups().length;
  }

  private resolve(matches: (r: Report) => boolean, resolution: ReportResolution, resolvedBy: string, at: Date): number {
    let count = 0;
    for (const report of this.reports) {
      if (!report.resolution && matches(report)) {
        Object.assign(report, { resolution, resolvedAt: at, resolvedBy });
        count++;
      }
    }
    return count;
  }

  private newestFirst(): Report[] {
    return [...this.reports].sort((a, b) => (a.id < b.id ? 1 : -1));
  }

  private groups(): OpenReportTarget[] {
    const groups = new Map<string, { latest: Report; reports: Report[] }>();
    for (const report of this.newestFirst().filter((r) => !r.resolution)) {
      const key = `${report.target.type}:${report.target.id}`;
      const group = groups.get(key) ?? { latest: report, reports: [] };
      group.reports.push(report);
      groups.set(key, group);
    }
    return [...groups.values()].map(({ latest, reports }) => {
      const counts = new Map<Report['reason'], number>();
      for (const r of reports) counts.set(r.reason, (counts.get(r.reason) ?? 0) + 1);
      return {
        target: latest.target,
        targetUserId: latest.targetUserId,
        openCount: reports.length,
        reasons: [...counts].map(([reason, count]) => ({ reason, count })).sort((a, b) => b.count - a.count || a.reason.localeCompare(b.reason)),
        latestId: latest.id,
        latestAt: latest.createdAt,
        excerpt: latest.excerpt,
      };
    });
  }
}

function sameTarget(a: ReportTarget, b: ReportTarget): boolean {
  return a.type === b.type && a.id === b.id;
}
