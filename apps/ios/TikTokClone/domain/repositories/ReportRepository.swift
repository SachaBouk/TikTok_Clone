// Port des signalements (module reports de l'API, ADR-038).
protocol ReportRepository: Sendable {
    // Idempotent : un second signalement de la même cible, encore ouvert, ne change rien.
    func report(_ target: ReportTarget, reason: ReportReason, details: String?) async throws
}
