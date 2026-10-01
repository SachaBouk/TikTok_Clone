import { Injectable } from '@nestjs/common';
import { Prisma } from '../../../generated/prisma/client';
import { PrismaService } from '../../../database/prisma.service';
import type { NewReport, OpenReportTarget, Report, ReportReason, ReportResolution, ReportTarget, ReportTargetType } from '../domain/report';
import { ReportRepository } from '../domain/report.repository';

const reportSelect = {
  id: true,
  reporterId: true,
  targetType: true,
  targetId: true,
  targetUserId: true,
  reason: true,
  details: true,
  excerpt: true,
  createdAt: true,
  resolution: true,
  resolvedAt: true,
  resolvedById: true,
} as const;

interface OpenTargetRow {
  target_type: ReportTargetType;
  target_id: string;
  target_user_id: string;
  open_count: number;
  latest_id: string;
  latest_at: Date;
  excerpt: string | null;
}

@Injectable()
export class PrismaReportRepository extends ReportRepository {
  constructor(private readonly prisma: PrismaService) {
    super();
  }

  // ON CONFLICT DO NOTHING sur l'index unique partiel `reports_open_key` : un doublon ouvert n'ajoute rien.
  async create(report: NewReport): Promise<boolean> {
    const { count } = await this.prisma.report.createMany({
      data: {
        reporterId: report.reporterId,
        targetType: report.target.type,
        targetId: report.target.id,
        targetUserId: report.targetUserId,
        reason: report.reason,
        details: report.details,
        excerpt: report.excerpt,
      },
      skipDuplicates: true,
    });
    return count === 1;
  }

  // Regroupement en SQL sur les seuls signalements ouverts (index partiel `reports_open_idx`) : une ligne par cible,
  // avec le signalement le plus récent (UUID v7 : l'ordre du texte est l'ordre du temps), puis les motifs comptés.
  async listOpenTargets(beforeId: string | null, limit: number): Promise<OpenReportTarget[]> {
    const before = beforeId ? Prisma.sql`WHERE g.latest_id < ${beforeId}::uuid` : Prisma.empty;
    return this.withReasons(await this.openTargets(Prisma.empty, before, limit));
  }

  async findOpenTarget(target: ReportTarget): Promise<OpenReportTarget | null> {
    const where = Prisma.sql`AND target_type = ${target.type}::report_target_type AND target_id = ${target.id}::uuid`;
    const [row] = await this.withReasons(await this.openTargets(where, Prisma.empty, 1));
    return row ?? null;
  }

  async listForTarget(target: ReportTarget, limit: number): Promise<Report[]> {
    const rows = await this.prisma.report.findMany({
      where: { targetType: target.type, targetId: target.id },
      orderBy: { id: 'desc' },
      take: limit,
      select: reportSelect,
    });
    return rows.map(toReport);
  }

  async resolveTarget(target: ReportTarget, resolution: ReportResolution, resolvedBy: string, at: Date): Promise<number> {
    const { count } = await this.prisma.report.updateMany({
      where: { targetType: target.type, targetId: target.id, resolution: null },
      data: { resolution, resolvedAt: at, resolvedById: resolvedBy },
    });
    return count;
  }

  async resolveForUser(targetUserId: string, resolution: ReportResolution, resolvedBy: string, at: Date): Promise<number> {
    const { count } = await this.prisma.report.updateMany({
      where: { targetUserId, resolution: null },
      data: { resolution, resolvedAt: at, resolvedById: resolvedBy },
    });
    return count;
  }

  async countOpenTargets(): Promise<number> {
    const [row] = await this.prisma.$queryRaw<{ count: number }[]>`
      SELECT count(*)::int AS count FROM (SELECT 1 FROM reports WHERE resolution IS NULL GROUP BY target_type, target_id) AS targets`;
    return row?.count ?? 0;
  }

  private openTargets(where: Prisma.Sql, before: Prisma.Sql, limit: number): Promise<OpenTargetRow[]> {
    return this.prisma.$queryRaw<OpenTargetRow[]>`
      WITH g AS (
        SELECT target_type, target_id, count(*)::int AS open_count, max(report_id::text)::uuid AS latest_id
        FROM reports
        WHERE resolution IS NULL ${where}
        GROUP BY target_type, target_id
      )
      SELECT g.target_type::text AS target_type, g.target_id::text AS target_id, r.target_user_id::text AS target_user_id,
             g.open_count, g.latest_id::text AS latest_id, r.created_at AS latest_at, r.excerpt
      FROM g JOIN reports r ON r.report_id = g.latest_id
      ${before}
      ORDER BY g.latest_id DESC
      LIMIT ${limit}`;
  }

  private async withReasons(rows: OpenTargetRow[]): Promise<OpenReportTarget[]> {
    if (rows.length === 0) return [];
    const counts = await this.prisma.report.groupBy({
      by: ['targetType', 'targetId', 'reason'],
      where: { resolution: null, targetId: { in: rows.map((row) => row.target_id) } },
      _count: { _all: true },
    });
    return rows.map((row) => ({
      target: { type: row.target_type, id: row.target_id },
      targetUserId: row.target_user_id,
      openCount: row.open_count,
      reasons: counts
        .filter((c) => c.targetType === row.target_type && c.targetId === row.target_id)
        .map((c) => ({ reason: c.reason as ReportReason, count: c._count._all }))
        .sort((a, b) => b.count - a.count || a.reason.localeCompare(b.reason)),
      latestId: row.latest_id,
      latestAt: row.latest_at,
      excerpt: row.excerpt,
    }));
  }
}

function toReport(row: Prisma.ReportGetPayload<{ select: typeof reportSelect }>): Report {
  return {
    id: row.id,
    reporterId: row.reporterId,
    target: { type: row.targetType, id: row.targetId },
    targetUserId: row.targetUserId,
    reason: row.reason,
    details: row.details,
    excerpt: row.excerpt,
    createdAt: row.createdAt,
    resolution: row.resolution,
    resolvedAt: row.resolvedAt,
    resolvedBy: row.resolvedById,
  };
}
