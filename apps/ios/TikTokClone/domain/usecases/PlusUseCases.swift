// Cas d'usage de l'abonnement « Plus » (ADR-073).
struct LoadPlusStatusUseCase: Sendable {
    let plus: any PlusRepository

    func callAsFunction() async throws -> PlusStatus {
        try await plus.status()
    }
}
