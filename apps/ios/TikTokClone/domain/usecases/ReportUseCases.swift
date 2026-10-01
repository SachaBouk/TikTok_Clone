// Cas d'usage des signalements (ADR-038).
struct SendReportUseCase: Sendable {
    let reports: any ReportRepository

    func callAsFunction(_ target: ReportTarget, reason: ReportReason, details: String) async throws {
        let details = ReportRules.sanitizedDetails(details)
        if let details, details.count > ReportRules.maxDetailsLength {
            throw AppError.rejected("La précision fait au plus \(ReportRules.maxDetailsLength) caractères.")
        }
        try await reports.report(target, reason: reason, details: details)
    }
}
