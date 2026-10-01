import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import type { ReportTargetType } from '@repo/shared';
import { ConfirmAction } from '@/components/confirm-action';
import { ReportTargetPreview } from '@/components/report-target-preview';
import { SuspendAccount } from '@/components/suspend-account';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { dismissReports, removeComment, removeVideo } from '@/controllers/moderation.actions';
import { formatDateTime } from '@/lib/format';
import { REPORT_REASON_LABELS, REPORT_RESOLUTION_LABELS, REPORT_TARGET_TYPES } from '@/lib/report-labels';
import { getReportTarget } from '@/models/reports.model';

export const metadata: Metadata = { title: 'Signalement' };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Une cible signalée (ADR-038) : ses signalements, et les décisions possibles. Supprimer le contenu ou suspendre le
// compte clôt les signalements ouverts ; « Classer sans suite » les clôt en laissant le contenu en ligne.
export default async function ReportTargetPage({ params }: { params: Promise<{ type: string; id: string }> }) {
  const { type, id } = await params;
  if (!REPORT_TARGET_TYPES.includes(type as ReportTargetType) || !UUID.test(id)) notFound();
  const detail = await getReportTarget(type as ReportTargetType, id);
  if (!detail) notFound();
  const { target, reports } = detail;
  const isOpen = target.openCount > 0;
  const contentHref =
    target.targetType === 'video' ? `/videos/${target.targetId}` : target.targetType === 'comment' && target.videoId ? `/videos/${target.videoId}` : null;

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="flex flex-col gap-2">
          <h1 className="text-2xl font-semibold">Signalement</h1>
          <ReportTargetPreview target={target} />
          <p className="text-sm text-muted-foreground">
            Compte visé :{' '}
            <Link href={`/users/${target.targetUser.id}`} className="font-medium text-foreground hover:underline">
              @{target.targetUser.username}
            </Link>
          </p>
        </div>
        {contentHref && target.available && (
          <Button variant="outline" asChild>
            <Link href={contentHref}>{target.targetType === 'video' ? 'Voir la vidéo' : 'Voir la vidéo commentée'}</Link>
          </Button>
        )}
      </div>

      <Card>
        <CardHeader>
          <CardTitle>{isOpen ? `${target.openCount} signalement(s) en attente` : 'Aucun signalement en attente'}</CardTitle>
        </CardHeader>
        {isOpen && (
          <CardContent className="flex flex-wrap gap-2">
            {target.available && target.targetType === 'video' && (
              <ConfirmAction
                label="Supprimer la vidéo"
                title="Supprimer cette vidéo ?"
                description="Suppression définitive, comme par son auteur. Ses signalements ouverts sont clos. L’auteur n’est pas prévenu."
                confirmLabel="Supprimer"
                size="default"
                action={removeVideo.bind(null, target.targetId, null)}
              />
            )}
            {target.available && target.targetType === 'comment' && (
              <ConfirmAction
                label="Supprimer le commentaire"
                title="Supprimer ce commentaire ?"
                description="Suppression définitive. Ses signalements ouverts sont clos. L’auteur n’est pas prévenu."
                confirmLabel="Supprimer"
                size="default"
                action={removeComment.bind(null, target.targetId)}
              />
            )}
            <SuspendAccount userId={target.targetUser.id} username={target.targetUser.username} />
            <ConfirmAction
              label="Classer sans suite"
              title="Classer ces signalements sans suite ?"
              description="Le contenu reste en ligne. Il pourra être signalé de nouveau."
              confirmLabel="Classer sans suite"
              pendingLabel="Classement…"
              destructive={false}
              size="default"
              action={dismissReports.bind(null, target.targetType, target.targetId)}
            />
          </CardContent>
        )}
      </Card>

      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Date</TableHead>
            <TableHead>Signalé par</TableHead>
            <TableHead>Motif</TableHead>
            <TableHead>Précision</TableHead>
            <TableHead>Décision</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {reports.map((report) => (
            <TableRow key={report.id}>
              <TableCell className="text-muted-foreground">{formatDateTime(report.createdAt)}</TableCell>
              <TableCell>
                {report.reporter ? (
                  <Link href={`/users/${report.reporter.id}`} className="hover:underline">
                    @{report.reporter.username}
                  </Link>
                ) : (
                  <span className="text-muted-foreground">Compte supprimé</span>
                )}
              </TableCell>
              <TableCell>{REPORT_REASON_LABELS[report.reason]}</TableCell>
              <TableCell className="max-w-sm whitespace-normal">{report.details ?? '—'}</TableCell>
              <TableCell>
                {report.resolution ? (
                  <span className="flex flex-col">
                    <Badge variant="secondary">{REPORT_RESOLUTION_LABELS[report.resolution]}</Badge>
                    <span className="text-xs text-muted-foreground">
                      {report.resolvedAt && formatDateTime(report.resolvedAt)}
                      {report.resolvedBy ? ` · @${report.resolvedBy.username}` : ''}
                    </span>
                  </span>
                ) : (
                  <Badge variant="destructive">En attente</Badge>
                )}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
