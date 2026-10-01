import type { Metadata } from 'next';
import Link from 'next/link';
import { Pagination } from '@/components/pagination';
import { ReportTargetAccount, ReportTargetPreview } from '@/components/report-target-preview';
import { Badge } from '@/components/ui/badge';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { formatDateTime, formatNumber, withQuery } from '@/lib/format';
import { REPORT_REASON_LABELS } from '@/lib/report-labels';
import { listReportTargets } from '@/models/reports.model';

export const metadata: Metadata = { title: 'Signalements' };

// File de modération (ADR-038) : une ligne par vidéo, commentaire, message ou compte signalé, du plus récemment signalé au plus
// ancien. Rien n'est masqué avant une décision.
export default async function ReportsPage({ searchParams }: { searchParams: Promise<{ curseur?: string }> }) {
  const { curseur } = await searchParams;
  const page = await listReportTargets(curseur);

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-semibold">Signalements</h1>
      <p className="text-sm text-muted-foreground">
        Contenus et comptes signalés, en attente d’une décision : supprimer le contenu, suspendre le compte, ou classer sans suite.
      </p>
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Cible</TableHead>
            <TableHead>Compte visé</TableHead>
            <TableHead className="text-right">Signalements</TableHead>
            <TableHead>Motifs</TableHead>
            <TableHead>Dernier</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {page.items.map((target) => (
            <TableRow key={`${target.targetType}:${target.targetId}`}>
              <TableCell>
                <Link href={`/reports/${target.targetType}/${target.targetId}`}>
                  <ReportTargetPreview target={target} />
                </Link>
              </TableCell>
              <TableCell>
                <ReportTargetAccount target={target} />
              </TableCell>
              <TableCell className="text-right tabular-nums">{formatNumber(target.openCount)}</TableCell>
              <TableCell>
                <div className="flex flex-wrap gap-1">
                  {target.reasons.map(({ reason, count }) => (
                    <Badge key={reason} variant="secondary">
                      {REPORT_REASON_LABELS[reason]}
                      {count > 1 ? ` × ${count}` : ''}
                    </Badge>
                  ))}
                </div>
              </TableCell>
              <TableCell className="text-muted-foreground">{formatDateTime(target.latestAt)}</TableCell>
            </TableRow>
          ))}
          {page.items.length === 0 && (
            <TableRow>
              <TableCell colSpan={5} className="text-center text-muted-foreground">
                Aucun signalement en attente.
              </TableCell>
            </TableRow>
          )}
        </TableBody>
      </Table>
      <Pagination onFirstPage={!curseur} firstHref="/reports" nextHref={page.nextCursor ? withQuery('/reports', { curseur: page.nextCursor }) : null} />
    </div>
  );
}
