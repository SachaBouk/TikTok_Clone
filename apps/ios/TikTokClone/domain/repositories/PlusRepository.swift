// Abonnement « Plus » par l'API (ADR-073).
protocol PlusRepository: Sendable {
    func status() async throws -> PlusStatus
}
