import type { AdminReportTargetDto } from '@repo/shared';
import { Thumbnail } from '@/components/thumbnail';
import { Badge } from '@/components/ui/badge';
import { REPORT_TARGET_LABELS } from '@/lib/report-labels';

// Aperçu d'une cible signalée : type, miniature (vidéo) ou texte copié, et « supprimé » si elle a disparu.
export function ReportTargetPreview({ target }: { target: AdminReportTargetDto }) {
  return (
    <div className="flex items-center gap-3">
      {target.targetType === 'video' && <Thumbnail url={target.thumbnailUrl ?? null} />}
      <div className="flex min-w-0 flex-col gap-1">
        <span className="flex items-center gap-2">
          <Badge variant="outline">{REPORT_TARGET_LABELS[target.targetType]}</Badge>
          {!target.available && <Badge variant="destructive">Supprimé</Badge>}
        </span>
        <span className="line-clamp-2 max-w-md text-sm">
          {target.targetType === 'account' ? `@${target.targetUser.username}` : (target.excerpt ?? '—')}
        </span>
      </div>
    </div>
  );
}
