import type { NewReport, OpenReportTarget, Report, ReportResolution, ReportTarget, ResolvedReport } from './report';

// Port de la table reports (ADR-038).
export abstract class ReportRepository {
  // Faux si la personne a déjà un signalement ouvert sur cette cible (rien n'est ajouté).
  abstract create(report: NewReport): Promise<boolean>;
  // Cibles ayant des signalements ouverts, de la plus récemment signalée à la plus ancienne, strictement avant le
  // signalement `beforeId` (le `latestId` d'une cible déjà lue).
  abstract listOpenTargets(beforeId: string | null, limit: number): Promise<OpenReportTarget[]>;
  // La cible si elle a des signalements ouverts, sinon null.
  abstract findOpenTarget(target: ReportTarget): Promise<OpenReportTarget | null>;
  // Tous les signalements d'une cible, du plus récent au plus ancien.
  abstract listForTarget(target: ReportTarget, limit: number): Promise<Report[]>;
  // Clôt les signalements ouverts : d'une cible, ou de toutes les cibles d'un compte (compte, vidéos, commentaires,
  // messages). Renvoie les signalements clos.
  abstract resolveTarget(target: ReportTarget, resolution: ReportResolution, resolvedBy: string, at: Date): Promise<ResolvedReport[]>;
  abstract resolveForUser(targetUserId: string, resolution: ReportResolution, resolvedBy: string, at: Date): Promise<ResolvedReport[]>;
  abstract countOpenTargets(): Promise<number>;
}
